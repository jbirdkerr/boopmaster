-- Migration: Separate vulnerability scan 404s from service error rate in worker_health_stats

-- 1. Add total_scans column to worker_health_stats if not present
ALTER TABLE "public"."worker_health_stats"
  ADD COLUMN IF NOT EXISTS "total_scans" bigint NOT NULL DEFAULT 0;

-- 2. Clean up historical data in the singleton row:
-- Move excess requests (scans) out of total_requests and total_errors_4xx into total_scans
UPDATE public.worker_health_stats
SET
  total_scans = GREATEST(0, total_requests - (total_proxy_requests + total_metrics_requests + total_health_requests)),
  total_errors_4xx = GREATEST(0, total_errors_4xx - GREATEST(0, total_requests - (total_proxy_requests + total_metrics_requests + total_health_requests))),
  total_requests = total_proxy_requests + total_metrics_requests + total_health_requests,
  updated_at = now()
WHERE id = true;

-- 3. Replace record_worker_health RPC to track scans separately from errors and service requests
CREATE OR REPLACE FUNCTION public.record_worker_health(
  p_request_type          text,     -- 'proxy', 'metrics', 'health', 'not_found'
  p_status_code           int,
  p_latency_ms            int DEFAULT NULL,
  p_persist_latency_ms    int DEFAULT NULL,
  p_decode_success        boolean DEFAULT NULL,
  p_supabase_write_failed boolean DEFAULT false,
  p_posthog_proxy_failed  boolean DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.worker_health_stats SET
    total_requests           = total_requests +
      CASE WHEN p_request_type != 'not_found' THEN 1 ELSE 0 END,
    total_scans              = total_scans +
      CASE WHEN p_request_type = 'not_found' THEN 1 ELSE 0 END,
    total_proxy_requests     = total_proxy_requests +
      CASE WHEN p_request_type = 'proxy' THEN 1 ELSE 0 END,
    total_metrics_requests   = total_metrics_requests +
      CASE WHEN p_request_type = 'metrics' THEN 1 ELSE 0 END,
    total_health_requests    = total_health_requests +
      CASE WHEN p_request_type = 'health' THEN 1 ELSE 0 END,
    total_errors_4xx         = total_errors_4xx +
      CASE WHEN p_status_code >= 400 AND p_status_code < 500 AND p_request_type != 'not_found' THEN 1 ELSE 0 END,
    total_errors_5xx         = total_errors_5xx +
      CASE WHEN p_status_code >= 500 THEN 1 ELSE 0 END,
    total_supabase_write_failures = total_supabase_write_failures +
      CASE WHEN p_supabase_write_failed THEN 1 ELSE 0 END,
    total_posthog_proxy_failures = total_posthog_proxy_failures +
      CASE WHEN p_posthog_proxy_failed THEN 1 ELSE 0 END,
    total_decode_failures    = total_decode_failures +
      CASE WHEN p_decode_success IS NOT NULL AND NOT p_decode_success THEN 1 ELSE 0 END,
    total_decode_successes   = total_decode_successes +
      CASE WHEN p_decode_success IS NOT NULL AND p_decode_success THEN 1 ELSE 0 END,
    sum_metrics_latency_ms   = sum_metrics_latency_ms +
      CASE WHEN p_request_type = 'metrics' AND p_latency_ms IS NOT NULL THEN p_latency_ms ELSE 0 END,
    count_metrics_latency    = count_metrics_latency +
      CASE WHEN p_request_type = 'metrics' AND p_latency_ms IS NOT NULL THEN 1 ELSE 0 END,
    sum_proxy_latency_ms     = sum_proxy_latency_ms +
      CASE WHEN p_request_type = 'proxy' AND p_latency_ms IS NOT NULL THEN p_latency_ms ELSE 0 END,
    count_proxy_latency      = count_proxy_latency +
      CASE WHEN p_request_type = 'proxy' AND p_latency_ms IS NOT NULL THEN 1 ELSE 0 END,
    sum_persist_latency_ms   = sum_persist_latency_ms +
      CASE WHEN p_persist_latency_ms IS NOT NULL THEN p_persist_latency_ms ELSE 0 END,
    count_persist_latency    = count_persist_latency +
      CASE WHEN p_persist_latency_ms IS NOT NULL THEN 1 ELSE 0 END,
    updated_at = now()
  WHERE id = true;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_worker_health(text, int, int, int, boolean, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_worker_health(text, int, int, int, boolean, boolean, boolean) TO "service_role", "postgres";
