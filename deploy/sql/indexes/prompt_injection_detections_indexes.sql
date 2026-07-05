-- ============================================
-- Indexes for table: prompt_injection_detections
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_detections_request ON public.prompt_injection_detections USING btree (request_id);
CREATE INDEX idx_detections_risk ON public.prompt_injection_detections USING btree (tenant_id, risk_level) WHERE (blocked = true);
CREATE INDEX idx_detections_session ON public.prompt_injection_detections USING btree (session_key);
CREATE INDEX idx_detections_tenant_time ON public.prompt_injection_detections USING btree (tenant_id, detected_at DESC);
