CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE company (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        TEXT NOT NULL,
    slug        TEXT NOT NULL UNIQUE,
    logo_color  TEXT NOT NULL DEFAULT '#4F46E5',        -- drives the letter tile
    "values"    TEXT[] NOT NULL DEFAULT '{}',           -- from company site + reports
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX company_name_trgm ON company USING gin (name gin_trgm_ops);

CREATE TABLE role (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_id  BIGINT NOT NULL REFERENCES company(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    slug        TEXT NOT NULL,
    tech_stack  TEXT[] NOT NULL DEFAULT '{}',           -- rebuilt from parsed reports
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, slug)
);
CREATE INDEX role_name_trgm ON role USING gin (name gin_trgm_ops);

CREATE TABLE report (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_id          BIGINT NOT NULL REFERENCES role(id) ON DELETE CASCADE,
    cycle            TEXT NOT NULL CHECK (cycle IN ('spring_summer', 'fall_winter', 'winter_spring', 'summer_fall')),
    year             INT  NOT NULL CHECK (year BETWEEN 2000 AND 2100),
    offer            TEXT NOT NULL CHECK (offer IN ('yes', 'no', 'no_response', 'waiting')),
    positive         BOOLEAN NOT NULL,
    difficult        BOOLEAN NOT NULL,
    has_oa           BOOLEAN NOT NULL DEFAULT false,
    has_behavioral   BOOLEAN NOT NULL DEFAULT false,
    has_technical    BOOLEAN NOT NULL DEFAULT false,
    interview_count  INT NOT NULL CHECK (interview_count BETWEEN 1 AND 6),   -- 6 means "6+"
    applied_via      TEXT CHECK (applied_via IN ('a_round', 'b_round', 'c_round', 'direct')),
    process_text     TEXT NOT NULL CHECK (char_length(process_text) >= 100),
    questions_text   TEXT,
    helpful_count    INT NOT NULL DEFAULT 0,
    status           TEXT NOT NULL DEFAULT 'published' CHECK (status IN ('published', 'flagged', 'hidden')),
    edit_token_hash  TEXT NOT NULL,                     -- never store the raw token
    ip_hash          TEXT,                              -- never store the raw IP
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    parsed_at        TIMESTAMPTZ                        -- NULL = not parsed by the AI job yet
);
CREATE INDEX report_role_published ON report (role_id, created_at DESC) WHERE status = 'published';
CREATE INDEX report_unparsed ON report (id) WHERE parsed_at IS NULL;
CREATE INDEX report_ip_recent ON report (ip_hash, created_at);   -- rate limiting

CREATE TABLE interview_round (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    report_id     BIGINT NOT NULL REFERENCES report(id) ON DELETE CASCADE,
    round_order   INT NOT NULL,
    type          TEXT NOT NULL CHECK (type IN ('oa', 'recruiter', 'technical', 'behavioral', 'panel', 'superday', 'other')),
    format        TEXT,                                 -- e.g. "video call", "on-site", "HackerRank"
    duration_min  INT
);
CREATE INDEX interview_round_report ON interview_round (report_id);

CREATE TABLE interview_question (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    report_id   BIGINT NOT NULL REFERENCES report(id) ON DELETE CASCADE,
    round_type  TEXT,
    text        TEXT NOT NULL,
    topic_tags  TEXT[] NOT NULL DEFAULT '{}'
);
CREATE INDEX interview_question_report ON interview_question (report_id);

CREATE TABLE role_summary (
    role_id           BIGINT PRIMARY KEY REFERENCES role(id) ON DELETE CASCADE,
    report_count      INT NOT NULL,
    offer_rate        NUMERIC(5, 4),
    positive_rate     NUMERIC(5, 4),
    difficult_rate    NUMERIC(5, 4),
    outcome_counts    JSONB NOT NULL DEFAULT '{}',
    summary_line      TEXT,
    steps             JSONB NOT NULL DEFAULT '[]',
    practice          JSONB NOT NULL DEFAULT '[]',
    cited_report_ids  BIGINT[] NOT NULL DEFAULT '{}',
    generated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE helpful_vote (
    report_id   BIGINT NOT NULL REFERENCES report(id) ON DELETE CASCADE,
    ip_hash     TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (report_id, ip_hash)                    -- one vote per person per review
);

CREATE TABLE flag (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    report_id   BIGINT NOT NULL REFERENCES report(id) ON DELETE CASCADE,
    reason      TEXT,
    ip_hash     TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX flag_report ON flag (report_id);
