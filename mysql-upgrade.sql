-- Run once against the existing database before deploying the upgraded app.
USE javatechie;
ALTER TABLE orders_tbl MODIFY COLUMN id INT NOT NULL AUTO_INCREMENT;
