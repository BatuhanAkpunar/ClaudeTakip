-- `sample_device_time (device_id, t)` birincil anahtarla birebir aynı:
-- PRIMARY KEY (device_id, t) SQLite'ta zaten aynı sütunlarda bir dizin.
-- Kopya dizin hiçbir sorguyu hızlandırmıyor, ama her örnek yazımında ikinci
-- bir dizin girdisi yazdırıp depolama ve yazma kotası harcıyordu.
DROP INDEX IF EXISTS sample_device_time;
