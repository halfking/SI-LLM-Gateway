#!/bin/bash
#
# 临时探测脚本：定期探测credentials的健康状态
# 用法: ./scripts/probe_credentials.sh
# 或作为cron任务: */3 * * * * /path/to/probe_credentials.sh

set -e

# 数据库连接信息
DB_HOST="127.0.0.1"
DB_USER="llm_gateway"
DB_NAME="llm_gateway"
DB_PASSWORD="${PGPASSWORD:-}"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# 执行探测
probe_credential() {
    local cred_id=$1
    local cred_label=$2
    local provider_id=$3
    local base_url=$4
    local probe_model=$5
    local api_key=$6
    
    log "Probing credential $cred_id ($cred_label) with model $probe_model"
    
    # 构造请求URL
    local url="${base_url%/}/chat/completions"
    
    # 执行HTTP请求
    local start_time=$(date +%s%3N)
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        -d "{\"model\":\"$probe_model\",\"messages\":[{\"role\":\"user\",\"content\":\"probe\"}],\"max_tokens\":1,\"stream\":false}" \
        --connect-timeout 10 \
        --max-time 30 \
        2>&1)
    
    local end_time=$(date +%s%3N)
    local latency=$((end_time - start_time))
    
    # 解析响应
    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -n -1)
    
    local success=false
    local error_kind="unknown"
    local error_message=""
    
    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        # HTTP 2xx
        if echo "$body" | jq -e '.choices[0]' >/dev/null 2>&1; then
            success=true
            log "  ✅ SUCCESS - HTTP $http_code, ${latency}ms"
        else
            error_kind="empty_response"
            error_message="HTTP $http_code but empty or invalid response"
            log "  ❌ FAILED - $error_message, ${latency}ms"
        fi
    elif [[ "$http_code" == "000" ]]; then
        error_kind="network"
        error_message="Connection failed or timeout"
        log "  ❌ FAILED - $error_message"
    elif [[ "$http_code" == "429" ]]; then
        error_kind="rate_limit"
        error_message="Rate limited"
        log "  ⚠️  RATE LIMITED - HTTP $http_code, ${latency}ms"
    else
        error_kind="http_error"
        error_message="HTTP $http_code"
        log "  ❌ FAILED - HTTP $http_code, ${latency}ms"
    fi
    
    # 记录探测结果到数据库
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "
        INSERT INTO credential_probes (
            credential_id, provider_id, probe_model, success, 
            http_status, latency_ms, error_kind, error_message, 
            response_preview, triggered_by
        ) VALUES (
            $cred_id, $provider_id, '$probe_model', $success,
            $([ "$http_code" != "000" ] && echo "$http_code" || echo "NULL"), 
            $latency, 
            $([ -n "$error_kind" ] && echo "'$error_kind'" || echo "NULL"),
            $([ -n "$error_message" ] && echo "'${error_message//\'/\'\'}'" || echo "NULL"),
            $([ ${#body} -gt 0 ] && echo "'$(echo "$body" | head -c 200 | sed "s/'/''/g")'" || echo "NULL"),
            'script'
        );
    " >/dev/null 2>&1
    
    # 更新credential状态
    if [ "$success" = true ]; then
        # 成功：重置失败计数
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "
            UPDATE credentials 
            SET probe_consecutive_failures = 0,
                last_probe_success = true,
                last_probe_at = NOW(),
                availability_state = 'ready'
            WHERE id = $cred_id;
        " >/dev/null 2>&1
    else
        # 失败：增加失败计数，检查是否超过阈值
        local failures=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "
            UPDATE credentials 
            SET probe_consecutive_failures = probe_consecutive_failures + 1,
                last_probe_success = false,
                last_probe_at = NOW()
            WHERE id = $cred_id
            RETURNING probe_consecutive_failures;
        " | xargs)
        
        local threshold=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "
            SELECT probe_failure_threshold FROM credentials WHERE id = $cred_id;
        " | xargs)
        
        if [ "$failures" -ge "$threshold" ]; then
            log "  ⚠️  Marking credential as cooling (failures: $failures >= $threshold)"
            PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c "
                UPDATE credentials 
                SET availability_state = 'cooling',
                    cooling_until = NOW() + INTERVAL '5 minutes',
                    state_reason_code = 'probe_failed',
                    state_reason_detail = 'Probe failed $failures times consecutively'
                WHERE id = $cred_id;
            " >/dev/null 2>&1
        fi
    fi
}

# 主函数
main() {
    log "=== Starting credential probes ==="
    
    # 查询需要探测的credentials
    local query="
        SELECT 
            c.id, c.label, c.provider_id, p.base_url, 
            pc.probe_model, encode(c.secret_ciphertext, 'base64')
        FROM credentials c
        JOIN providers p ON p.id = c.provider_id
        JOIN credential_probe_configs pc ON pc.credential_id = c.id
        WHERE c.probe_enabled = true
          AND c.lifecycle_status = 'active'
          AND pc.enabled = true
          AND (
              c.last_probe_at IS NULL 
              OR c.last_probe_at < NOW() - (c.probe_interval_sec || ' seconds')::INTERVAL
          )
        ORDER BY c.last_probe_at NULLS FIRST, pc.priority
        LIMIT 10;
    "
    
    # 注意：这个脚本需要能解密secret_ciphertext
    # 实际环境中应该使用Go程序或有解密能力的工具
    
    log "Checking database for credentials to probe..."
    
    local count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) 
        FROM credentials c
        JOIN credential_probe_configs pc ON pc.credential_id = c.id
        WHERE c.probe_enabled = true
          AND c.lifecycle_status = 'active'
          AND pc.enabled = true
          AND (
              c.last_probe_at IS NULL 
              OR c.last_probe_at < NOW() - (c.probe_interval_sec || ' seconds')::INTERVAL
          );
    " | xargs)
    
    log "Found $count credentials to probe"
    
    if [ "$count" -eq 0 ]; then
        log "No credentials need probing at this time"
        return 0
    fi
    
    # 注意：实际探测需要解密API keys，这里只是示意
    log "⚠️  Note: Actual probing requires credential decryption capability"
    log "    Please use the Go-based probe service for production use"
    
    log "=== Probe run completed ==="
}

# 检查依赖
if ! command -v psql &> /dev/null; then
    echo "Error: psql not found. Please install PostgreSQL client."
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "Error: curl not found. Please install curl."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq not found. Please install jq."
    exit 1
fi

# 运行
main "$@"
