ALTER TABLE exercises
ADD COLUMN time_based INTEGER NOT NULL DEFAULT 0 CHECK (time_based IN (0, 1));
