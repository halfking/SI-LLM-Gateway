-- ===========================================================================
-- Object:   credential_model_state (rollback)
-- Type:     TABLE DROP
-- Schema:   public
-- Purpose:  回滚credential_model_state表
-- ===========================================================================

DROP TRIGGER IF EXISTS trg_cms_updated_at ON credential_model_state;
DROP FUNCTION IF EXISTS update_cms_updated_at();
DROP TABLE IF EXISTS credential_model_state CASCADE;
