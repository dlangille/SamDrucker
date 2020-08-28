-- Column: public.host.enabled

-- ALTER TABLE public.host DROP COLUMN enabled;

ALTER TABLE public.host
    ADD COLUMN enabled boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.host.enabled
    IS 'hosts are enabled by default
when no longer in service, set to false';
