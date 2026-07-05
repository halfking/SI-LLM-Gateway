-- ============================================
-- Indexes for table: response_format_anomalies
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_response_format_anomalies_detected_at ON public.response_format_anomalies USING btree (detected_at DESC);
CREATE INDEX idx_response_format_anomalies_provider ON public.response_format_anomalies USING btree (provider_code, client_model) WHERE (provider_code IS NOT NULL);
CREATE INDEX idx_response_format_anomalies_request_id ON public.response_format_anomalies USING btree (request_id);
CREATE INDEX idx_response_format_anomalies_type ON public.response_format_anomalies USING btree (anomaly_type, detected_at DESC);
CREATE INDEX idx_response_format_anomalies_unresolved ON public.response_format_anomalies USING btree (detected_at DESC) WHERE (NOT resolved);
