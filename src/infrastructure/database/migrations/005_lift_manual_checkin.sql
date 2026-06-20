ALTER TABLE lifts ADD COLUMN manual_checkin_status TEXT NOT NULL DEFAULT 'none';
ALTER TABLE lifts ADD COLUMN manual_checkin_source_lift_id INTEGER REFERENCES lifts(id);
