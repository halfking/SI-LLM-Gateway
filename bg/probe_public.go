// bg/probe_public.go — 公开的同步探测入口
//
// ProbeCredentialModel 探测指定 credential+model 是否可调用，供 anti-flap
// 双重验证等需要"同步拿到结果"的场景使用。复用本包已有的协议感知探测
// 能力（providercap + singleChatPing），不另造请求逻辑。
package bg

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kaixuan/llm-gateway-go/internal/providercap"
	"github.com/kaixuan/llm-gateway-go/internal/upstreamurl"
	"github.com/kaixuan/llm-gateway-go/secret"
)

// ProbeCredentialModel 发起一次最小 chat 探测，返回 (ok, errMsg)。
//
// 复用 providercap.Resolve 做协议适配（OpenAI / Anthropic / Volcano 等），
// 与后台 CredentialProbeV2 走同一套 auth-header 与端点解析逻辑，区别仅在
// 于这里探测的是传入的 model 而非 credential.default_probe_model。
func ProbeCredentialModel(
	ctx context.Context,
	db *pgxpool.Pool,
	keyring *secret.Keyring,
	encKey []byte,
	credentialID int,
	model string,
) (bool, string) {
	var baseURL, protocol string
	var ciphertext []byte
	err := db.QueryRow(ctx, `
		SELECT COALESCE(p.base_url, ''),
		       COALESCE(p.protocol, 'openai-completions'),
		       c.secret_ciphertext
		FROM credentials c
		JOIN providers p ON p.id = c.provider_id
		WHERE c.id = $1
	`, credentialID).Scan(&baseURL, &protocol, &ciphertext)
	if err != nil {
		return false, fmt.Sprintf("query credential: %v", err)
	}
	if baseURL == "" {
		return false, "empty base_url"
	}

	apiKey, err := decryptCiphertext(ciphertext, keyring, encKey)
	if err != nil {
		return false, fmt.Sprintf("decrypt: %v", err)
	}

	desc := providercap.Resolve(protocol, "")

	// 选探测端点：Anthropic 协议走 /v1/messages，其余走 chat-probe 端点。
	endpoint := upstreamurl.Build(baseURL, desc.ChatProbeEndpoint)
	if endpoint == "" {
		endpoint = upstreamurl.Build(baseURL, upstreamurl.EpChatCompletions)
	}
	if endpoint == "" {
		return false, "unresolved probe endpoint"
	}

	result := singleChatPing(ctx, endpoint, apiKey, model, desc)
	if result.status == "ok" {
		return true, ""
	}
	if result.errMsg != "" {
		return false, fmt.Sprintf("%s: %s", result.status, result.errMsg)
	}
	return false, result.status
}
