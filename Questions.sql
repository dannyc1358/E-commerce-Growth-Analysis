-- BUSINESS QUESTIONS
"ANALYSIS 1: Revenue Trends Over Time"
-- Business Question: "Is our business growing? What are the revenue trends?"
	-- Monthly Revenue
SELECT
	TO_CHAR(o.order_purchase_timestamp, 'YYYY-MM') as month,
	COUNT(DISTINCT o.order_id) as total_orders,
	COUNT(DISTINCT o.customer_id) as total_customers,
	ROUND(SUM(oi.price + oi.freight_value)::numeric, 2) as total_revenue,
	ROUND(AVG(oi.price + oi.freight_value)::numeric, 2) as avg_order_value
FROM orders o
JOIN order_items oi on o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY TO_CHAR(o.order_purchase_timestamp, 'YYYY-MM')
ORDER BY month;

	-- MoM Growth
WITH monthly_revenue AS (
	SELECT
		TO_CHAR(o.order_purchase_timestamp, 'YYYY-MM') as month,
		ROUND(SUM(oi.price + oi.freight_value)::numeric, 2) as revenue
	FROM orders o
	JOIN order_items oi ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY TO_CHAR(o.order_purchase_timestamp, 'YYYY-MM')
)
SELECT
	month,
	revenue,
	LAG(revenue) OVER (ORDER BY month) as prev_month_revenue,
	ROUND((revenue - LAG(revenue) OVER (ORDER BY month))::numeric, 2) as revenue_change,
	ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month)) /
		NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 2) as pct_change
FROM monthly_revenue
ORDER BY month;
"ANALYSIS 2: Customer Segmentation (RFM Analysis)"
-- Business Question: "Who are our best customers? How should we segment them?"
	-- RFM (Recency, Frequency, Monetary) Segmentation Query
WITH customer_metrics AS (
	SELECT
		c.customer_unique_id,
		COUNT(DISTINCT o.order_id) as frequency,
		ROUND(SUM(oi.price + oi.freight_value)::numeric, 2) as monetary,
		MAX(o.order_purchase_timestamp) as last_purchase_date,
		'2018-08-31'::date - MAX(o.order_purchase_timestamp)::date as recency_days
	FROM customers c
	JOIN orders o ON c.customer_id = o.customer_id
	JOIN order_items oi ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY c.customer_unique_id
),
rfm_scores AS (
	SELECT
		customer_unique_id,
		frequency,
		monetary,
		recency_days,
		NTILE(4) OVER (ORDER BY recency_days) as R_score,
		NTILE(4) OVER (ORDER BY frequency DESC) as F_score,
		NTILE(4) OVER (ORDER BY monetary DESC) as M_score
	FROM customer_metrics
)
SELECT
	customer_unique_id,
	R_score,
	F_score,
	M_score,
	(R_score + F_score + M_score) as RFM_total,
	CASE
		WHEN R_score >= 3 AND F_score >= 3 AND M_score >= 3 THEN 'Champions'
		WHEN R_score >= 3 AND F_score >= 3 THEN 'Loyal Customers'
		WHEN R_score >= 3 AND M_score >= 3 THEN 'Big Spenders'
		WHEN R_score >= 3 AND F_score >= 3  THEN 'Potential Loyalists'
		WHEN R_score = 2 AND F_score >= 3  THEN 'At Risk'
		WHEN R_score <= 2 AND F_score >= 3  THEN 'Cant Lose Them'
		WHEN R_score <= 2 AND F_score >= 3 AND M_score <= 2 THEN 'Lost'
		ELSE 'Others'
	END as customer_segment
FROM rfm_scores;
	-- Summary
WITH customer_metrics AS (
    SELECT 
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) as frequency,
        ROUND(SUM(oi.price + oi.freight_value)::numeric, 2) as monetary,
        '2018-08-31'::date - MAX(o.order_purchase_timestamp)::date as recency_days
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scores AS (
    SELECT 
        customer_unique_id,
        frequency,
        monetary,
        recency_days,
        NTILE(4) OVER (ORDER BY recency_days) as R_score,
        NTILE(4) OVER (ORDER BY frequency DESC) as F_score,
        NTILE(4) OVER (ORDER BY monetary DESC) as M_score
    FROM customer_metrics
),
segments AS (
    SELECT 
        CASE 
            WHEN R_score >= 3 AND F_score >= 3 AND M_score >= 3 THEN 'Champions'
            WHEN R_score >= 3 AND F_score >= 2 THEN 'Loyal Customers'
            WHEN R_score >= 3 AND M_score >= 3 THEN 'Big Spenders'
            WHEN R_score >= 3 AND F_score = 1 THEN 'Potential Loyalists'
            WHEN R_score = 2 AND F_score >= 2 THEN 'At Risk'
            WHEN R_score <= 2 AND F_score >= 3 THEN 'Cant Lose Them'
            WHEN R_score <= 2 AND F_score <= 2 AND M_score <= 2 THEN 'Lost'
            ELSE 'Others'
        END as customer_segment,
        frequency,
        monetary,
        recency_days
    FROM rfm_scores
)
SELECT 
    customer_segment,
    COUNT(*) as customer_count,
    ROUND(AVG(monetary)::numeric, 2) as avg_lifetime_value,
    ROUND(AVG(frequency)::numeric, 2) as avg_order_frequency,
    ROUND(AVG(recency_days)::numeric, 0) as avg_days_since_purchase
FROM segments
GROUP BY customer_segment
ORDER BY customer_count DESC;
"ANALYSIS 3: Cohort Retention Analysis"
-- Business Question: "Do customers come back? What's our retention rate?"
	-- Cohort Retention Query
WITH customer_cohorts AS (
    SELECT 
        c.customer_unique_id,
        TO_CHAR(MIN(o.order_purchase_timestamp), 'YYYY-MM') as cohort_month,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp)) as first_purchase_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_orders AS (
    SELECT 
        c.customer_unique_id,
        cc.cohort_month,
        TO_CHAR(o.order_purchase_timestamp, 'YYYY-MM') as order_month,
        EXTRACT(YEAR FROM AGE(DATE_TRUNC('month', o.order_purchase_timestamp), cc.first_purchase_month)) * 12 +
        EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', o.order_purchase_timestamp), cc.first_purchase_month)) as months_since_first
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN customer_cohorts cc ON c.customer_unique_id = cc.customer_unique_id
    WHERE o.order_status = 'delivered'
)
SELECT 
    cohort_month,
    months_since_first,
    COUNT(DISTINCT customer_unique_id) as active_customers
FROM customer_orders
WHERE months_since_first <= 12
GROUP BY cohort_month, months_since_first
ORDER BY cohort_month, months_since_first;
	--Retention Rate
WITH customer_cohorts AS (
    SELECT 
        c.customer_unique_id,
        TO_CHAR(MIN(o.order_purchase_timestamp), 'YYYY-MM') as cohort_month,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp)) as first_purchase_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
cohort_sizes AS (
    SELECT 
        cohort_month,
        COUNT(DISTINCT customer_unique_id) as cohort_size
    FROM customer_cohorts
    GROUP BY cohort_month
),
customer_orders AS (
    SELECT 
        c.customer_unique_id,
        cc.cohort_month,
        EXTRACT(YEAR FROM AGE(DATE_TRUNC('month', o.order_purchase_timestamp), cc.first_purchase_month)) * 12 +
        EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', o.order_purchase_timestamp), cc.first_purchase_month)) as months_since_first
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN customer_cohorts cc ON c.customer_unique_id = cc.customer_unique_id
    WHERE o.order_status = 'delivered'
),
cohort_activity AS (
    SELECT 
        cohort_month,
        months_since_first,
        COUNT(DISTINCT customer_unique_id) as active_customers
    FROM customer_orders
    WHERE months_since_first <= 12
    GROUP BY cohort_month, months_since_first
)
SELECT 
    ca.cohort_month,
    cs.cohort_size,
    ca.months_since_first,
    ca.active_customers,
    ROUND(100.0 * ca.active_customers / cs.cohort_size, 2) as retention_rate
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
ORDER BY ca.cohort_month, ca.months_since_first;
"ANALYSIS 4: Delivery Performance Analysis"
-- Business Question: "Are we delivering on time? Where are the problems?"
	-- Overall Performance
SELECT
	COUNT(*) as total_delivered_orders,
	ROUND(AVG(order_delivered_customer_date::date - order_purchase_timestamp::date)::numeric, 1) as avg_actual_delivery_days,
	ROUND(AVG(order_estimated_delivery_date::date - order_purchase_timestamp::date)::numeric, 1) as avg_estimated_delivery_days,
	SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date
		THEN 1 ELSE 0 END) as late_deliveries,
	ROUND(100.0 * SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date
		THEN 1 ELSE 0 END) / COUNT(*), 2) as late_delivery_rate
FROM orders
WHERE order_status = 'delivered'
	AND order_delivered_customer_date IS NOT NULL;
	-- Performance by State
SELECT
	c.customer_state,
	COUNT(*) as orders,
	ROUND(AVG(o.order_delivered_customer_date::date - o.order_purchase_timestamp::date)::numeric, 1) as avg_delivery_days,
	ROUND(100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
		THEN 1 ELSE 0 END) / COUNT(*), 2) as late_delivery_rate
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
	AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
HAVING COUNT(*) > 100
ORDER BY late_delivery_rate DESC
LIMIT 15;
	-- Performance over Months
SELECT
	TO_CHAR(order_purchase_timestamp, 'YYYY-MM') as month,
	ROUND(AVG(order_delivered_customer_date::date - order_purchase_timestamp::date)::numeric, 1) as avg_delivery_days,
	ROUND(100.0 * SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date
		THEN 1 ELSE 0 END) / COUNT(*), 2) as late_rate
FROM orders
WHERE order_status = 'delivered'
	AND order_delivered_customer_date IS NOT NULL
GROUP BY TO_CHAR(order_purchase_timestamp, 'YYYY-MM')
ORDER BY month;
"ANALYSIS 5: Product Performance"
-- Business Question: "Which products/categories drive revenue? Which underperform?"
	-- TOP 15 Categories
SELECT
	p.product_category_name as category,
	COUNT(DISTINCT oi.order_id) as orders,
	ROUND(SUM(oi.price)::numeric, 2) as product_revenue,
	ROUND(SUM(oi.freight_value)::numeric, 2) as freight_revenue,
	ROUND(SUM(oi.price + oi.freight_value)::numeric, 2) as total_revenue,
	ROUND(AVG(oi.price)::numeric, 2) as avg_product_price,
	ROUND(AVG(r.review_score)::numeric, 2) as avg_review_score
FROM order_items oi
JOIN products p on oi.product_id = p.product_id
LEFT JOIN orders o on oi.order_id = o.order_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
	AND p.product_category_name IS NOT NULL
GROUP BY p.product_category_name
ORDER BY total_revenue DESC
LIMIT 15;
	-- Category performance over time
SELECT
	TO_CHAR(o.order_purchase_timestamp, 'YYYY-MM') as month,
	p.product_category_name as category,
	COUNT(DISTINCT oi.order_id) as orders,
	ROUND(SUM(oi.price)::numeric, 2) as revenue
FROM orders o
JOIN order_items oi on o.order_id = oi.order_id
JOIN products p on oi.product_id = p.product_id
WHERE o.order_status = 'delivered'
	AND p.product_category_name IS NOT NULL
GROUP BY month, category
ORDER BY month, category;
"ANALYSIS 6: Payment Analysis"
-- Business Question: "How do customers prefer to pay? Does payment method affect behavior?"
	-- Payment Method Overview
SELECT
	payment_type,
	COUNT(DISTINCT order_id) as orders,
	ROUND(SUM(payment_value)::numeric, 2) as total_value,
	ROUND(AVG(payment_value)::numeric, 2) as avg_payment_value,
	ROUND(AVG(payment_installments)::numeric, 1) as avg_installments
FROM order_payments
GROUP BY payment_type
ORDER BY orders DESC;
"ANALYSIS 7: Hourly/Daily Purchase Patterns "
-- Business Question: "When do customers shop? Can we optimize for peak times?"
	-- Orders By Hour of the Day
SELECT
	EXTRACT(HOUR FROM order_purchase_timestamp) as hour,
	COUNT(*) as orders,
	ROUND(AVG(payment_value)::numeric, 2) as avg_order_value
FROM orders o
JOIN order_payments op on o.order_id = op.order_id
WHERE o.order_status = 'delivered'
GROUP BY hour
ORDER BY hour;

	-- Orders by Day of Week
SELECT
	TO_CHAR(order_purchase_timestamp, 'Day') as day_of_week,
	EXTRACT(DOW FROM order_purchase_timestamp) as day_num,
	COUNT(*) as orders,
	ROUND(SUM(payment_value)::numeric, 2) as revenue
FROM orders o
JOIN order_payments op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
GROUP BY day_of_week, day_num
ORDER BY day_num;

	--Heatmap
SELECT 
    TO_CHAR(order_purchase_timestamp, 'Day') as day_of_week,
    EXTRACT(DOW FROM order_purchase_timestamp) as day_num,
    EXTRACT(HOUR FROM order_purchase_timestamp) as hour,
    COUNT(*) as orders
FROM orders
WHERE order_status = 'delivered'
GROUP BY day_of_week, day_num, hour
ORDER BY day_num, hour;
"ANALYSIS 8: Customer Lifetime Value (CLV)"
-- Business Question: "What's the typical customer worth? How do we increase CLV?"
WITH customer_value AS (
	SELECT
		c.customer_unique_id,
		COUNT(DISTINCT o.order_id) as total_orders,
		ROUND(SUM(oi.price + oi.freight_value)::numeric, 2) as lifetime_value,
		MIN(o.order_purchase_timestamp) as first_purchase,
		MAX(o.order_purchase_timestamp) as last_purchase,
		MAX(o.order_purchase_timestamp)::date - MIN(o.order_purchase_timestamp)::date as customer_lifespan_days,
		ROUND(AVG(r.review_score)::numeric, 2) as avg_review_score
	FROM customers c
	JOIN orders o ON c.customer_id = o.customer_id
	JOIN order_items oi on o.order_id = oi.order_id
	LEFT JOIN order_reviews r ON o.order_id = r.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY c.customer_unique_id
)
SELECT
	CASE
		WHEN total_orders = 1 THEN 'One-time customer'
		WHEN total_orders = 2 THEN 'Two-time customer'
		WHEN total_orders >= 3 THEN 'Repeat Customer (3+)'
	END as customer_type,
	COUNT(*) as customer_count,
	ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM customer_value), 2) as pct_of_customers,
	ROUND(AVG(lifetime_value)::numeric, 2) as avg_clv,
	ROUND(AVG(customer_lifespan_days)::numeric, 0) as avg_lifespan_days,
	ROUND(AVG(avg_review_score)::numeric, 2) as avg_review
FROM customer_value
GROUP BY
	CASE
		WHEN total_orders = 1 THEN 'One-time customer'
		WHEN total_orders = 2 THEN 'Two-time customer'
		WHEN total_orders >= 3 THEN 'Repeat Customer (3+)'
	END;