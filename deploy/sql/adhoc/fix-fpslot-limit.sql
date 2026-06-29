-- 修复 minimax-prod-1 的 fp_slot_limit 配置
-- 问题：25 个 slot 对 2-3 个用户过多，且并发请求之前没有共享机制
-- 解决：降低到 5 个 slot（3 个实际用户 + 2 个冗余）

BEGIN;

-- 1. 查看修改前的配置
SELECT 
    id,
    label,
    concurrency_limit,
    fp_slot_limit AS fp_slot_limit_before,
    updated_at
FROM credentials
WHERE id = 6;

-- 2. 更新 fp_slot_limit
UPDATE credentials
SET fp_slot_limit = 5,
    updated_at = NOW()
WHERE id = 6;

-- 3. 确认修改后的配置
SELECT 
    id,
    label,
    concurrency_limit,
    fp_slot_limit AS fp_slot_limit_after,
    updated_at
FROM credentials
WHERE id = 6;

COMMIT;

-- 预期结果：
-- fp_slot_limit: 25 → 5
-- 
-- 理由：
-- - 实际用户数：2-3 个
-- - 理论需要：3 个 slot（每个用户 1 个，代码修复后并发共享）
-- - 设置为 5：留 2 个冗余槽位，应对临时新用户或会话切换
-- 
-- 回滚方法（如需要）：
-- UPDATE credentials SET fp_slot_limit = 25, updated_at = NOW() WHERE id = 6;
