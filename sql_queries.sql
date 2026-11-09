-- 02_analysis_queries_sqlserver.sql : T-SQL (SQL Server / SSMS) version
-- Run 01_schema_and_data.sql first (same database), then run this file.
USE ecommerce;
GO

-- Q01 SELECT + WHERE: customers from Coimbatore
SELECT customer_id, name, city, signup_date
FROM customers
WHERE city = 'Coimbatore';

-- Q02 ORDER BY: top 10 most expensive products
SELECT TOP 10 product_name, category, price
FROM products
ORDER BY price DESC;

-- Q03 GROUP BY + COUNT: orders per status
SELECT status, COUNT(*) AS total_orders
FROM orders
GROUP BY status
ORDER BY total_orders DESC;

-- Q04 Aggregates: revenue summary of delivered orders
SELECT COUNT(DISTINCT o.order_id)                  AS delivered_orders,
       SUM(oi.quantity * oi.unit_price)            AS total_revenue,
       ROUND(AVG(oi.quantity * oi.unit_price), 2)  AS avg_line_value,
       MIN(oi.quantity * oi.unit_price)            AS min_line_value,
       MAX(oi.quantity * oi.unit_price)            AS max_line_value
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status = 'Delivered';

-- Q05 INNER JOIN: revenue by product category
SELECT p.category,
       SUM(oi.quantity)                  AS units_sold,
       SUM(oi.quantity * oi.unit_price)  AS revenue
FROM order_items oi
INNER JOIN products p ON p.product_id = oi.product_id
GROUP BY p.category
ORDER BY revenue DESC;

-- Q06 GROUP BY + HAVING: cities with more than 10 orders
SELECT c.city, COUNT(o.order_id) AS orders_count
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
WHERE c.city IS NOT NULL
GROUP BY c.city
HAVING COUNT(o.order_id) > 10
ORDER BY orders_count DESC;

-- Q07 LEFT JOIN: customers who never placed an order
SELECT c.customer_id, c.name, c.city
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;

-- Q08 RIGHT JOIN: products that were never sold
SELECT p.product_id, p.product_name, p.category
FROM order_items oi
RIGHT JOIN products p ON p.product_id = oi.product_id
WHERE oi.item_id IS NULL;

-- Q09 Average revenue per user (ARPU)
SELECT ROUND(SUM(oi.quantity * oi.unit_price) * 1.0 / COUNT(DISTINCT o.customer_id), 2) AS avg_revenue_per_user
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status NOT IN ('Cancelled','Returned');

-- Q10 Top 10 spenders with RANK()
SELECT TOP 10 c.customer_id, c.name,
       COUNT(DISTINCT o.order_id)        AS orders,
       SUM(oi.quantity * oi.unit_price)  AS total_spent,
       RANK() OVER (ORDER BY SUM(oi.quantity * oi.unit_price) DESC) AS spend_rank
FROM customers c
JOIN orders o       ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id   = o.order_id
WHERE o.status NOT IN ('Cancelled','Returned')
GROUP BY c.customer_id, c.name
ORDER BY spend_rank;

-- Q11 Subquery (scalar): products priced above average
SELECT product_name, category, price
FROM products
WHERE price > (SELECT AVG(price) FROM products)
ORDER BY price DESC;

-- Q12 Subquery (IN): customers who bought from 'Fashion'
SELECT DISTINCT c.customer_id, c.name
FROM customers c
WHERE c.customer_id IN (
    SELECT o.customer_id
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN products p     ON p.product_id = oi.product_id
    WHERE p.category = 'Fashion')
ORDER BY c.customer_id;

-- Q13 Subquery (derived table): customers spending above the average customer
SELECT t.name, t.total_spent
FROM (SELECT c.customer_id, c.name, SUM(oi.quantity * oi.unit_price) AS total_spent
      FROM customers c
      JOIN orders o       ON o.customer_id = c.customer_id
      JOIN order_items oi ON oi.order_id   = o.order_id
      GROUP BY c.customer_id, c.name) t
WHERE t.total_spent > (SELECT AVG(s.total_spent)
                       FROM (SELECT SUM(oi.quantity * oi.unit_price) AS total_spent
                             FROM orders o JOIN order_items oi ON oi.order_id = o.order_id
                             GROUP BY o.customer_id) s)
ORDER BY t.total_spent DESC;

-- Q14 Monthly revenue trend
SELECT CONVERT(CHAR(7), o.order_date, 120)  AS [month],
       COUNT(DISTINCT o.order_id)           AS orders,
       SUM(oi.quantity * oi.unit_price)     AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.status NOT IN ('Cancelled','Returned')
GROUP BY CONVERT(CHAR(7), o.order_date, 120)
ORDER BY [month];

-- Q15 NULL handling: COALESCE
SELECT COALESCE(city, 'Unknown') AS city, COUNT(*) AS customers
FROM customers
GROUP BY COALESCE(city, 'Unknown')
ORDER BY customers DESC;

-- Q16 CASE WHEN: customer segmentation by spend
SELECT segment, COUNT(*) AS customers
FROM (SELECT c.customer_id,
             CASE WHEN COALESCE(SUM(oi.quantity*oi.unit_price),0) = 0 THEN 'No purchase'
                  WHEN SUM(oi.quantity*oi.unit_price) < 20000         THEN 'Low'
                  WHEN SUM(oi.quantity*oi.unit_price) < 50000         THEN 'Medium'
                  ELSE 'High' END AS segment
      FROM customers c
      LEFT JOIN orders o       ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON oi.order_id   = o.order_id
      GROUP BY c.customer_id) x
GROUP BY segment
ORDER BY customers DESC;
GO

-- Q17 CREATE VIEW: order totals  (CREATE VIEW must be alone in its batch -> GO)
DROP VIEW IF EXISTS v_order_totals;
GO
CREATE VIEW v_order_totals AS
SELECT o.order_id, o.customer_id, o.order_date, o.status,
       SUM(oi.quantity)                  AS total_units,
       SUM(oi.quantity * oi.unit_price)  AS order_value
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.customer_id, o.order_date, o.status;
GO
SELECT TOP 10 * FROM v_order_totals ORDER BY order_value DESC;
GO

-- Q18 CREATE VIEW: customer lifetime value, then query it
DROP VIEW IF EXISTS v_customer_ltv;
GO
CREATE VIEW v_customer_ltv AS
SELECT c.customer_id, c.name, COALESCE(c.city,'Unknown') AS city,
       COUNT(v.order_id)               AS orders,
       COALESCE(SUM(v.order_value),0)  AS lifetime_value
FROM customers c
LEFT JOIN v_order_totals v ON v.customer_id = c.customer_id AND v.status NOT IN ('Cancelled','Returned')
GROUP BY c.customer_id, c.name, c.city;
GO
SELECT city, COUNT(*) AS customers, ROUND(AVG(lifetime_value),2) AS avg_ltv
FROM v_customer_ltv
GROUP BY city
ORDER BY avg_ltv DESC;
GO

-- Q19 INDEX optimisation: BEFORE index
-- Turn on "Include Actual Execution Plan" (Ctrl+M) and look at the Messages tab for logical reads.
DROP INDEX IF EXISTS idx_orders_customer_date ON orders;
DROP INDEX IF EXISTS idx_items_order   ON order_items;
DROP INDEX IF EXISTS idx_items_product ON order_items;
GO
SET STATISTICS IO ON;
SELECT * FROM orders WHERE customer_id = 5 AND order_date >= '2025-06-01';
SET STATISTICS IO OFF;
GO

-- Q20 Create indexes
CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date);
CREATE INDEX idx_items_order          ON order_items(order_id);
CREATE INDEX idx_items_product        ON order_items(product_id);
GO
SELECT i.name AS index_name, OBJECT_NAME(i.object_id) AS on_table
FROM sys.indexes i
WHERE i.name LIKE 'idx[_]%';
GO

-- Q21 INDEX optimisation: AFTER index (compare plan: Table Scan -> Index Seek, and logical reads)
SET STATISTICS IO ON;
SELECT * FROM orders WHERE customer_id = 5 AND order_date >= '2025-06-01';
SET STATISTICS IO OFF;
GO
