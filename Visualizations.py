# Libraries and Packages setup
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from sqlalchemy import create_engine
from datetime import datetime

sns.set_style('darkgrid')
sns.set_palette('cubehelix')
plt.rcParams['figure.figsize'] = (12,6)
plt.rcParams['font.size'] = 10

engine = create_engine('postgresql://postgres:Crimsonzero1424@localhost:5432/E-Commerce')

conn = engine.connect()
print('Connected to database')

#Viz1
query1 = """
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
"""

revenue_df = pd.read_sql_query(query1, engine)
revenue_df['month'] = pd.to_datetime(revenue_df['month'])

fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12,10))

# Subplot 1: Revenue with 3-month moving average
revenue_df['revenue_ma3'] = revenue_df['revenue'].rolling(window=3).mean()
ax1.plot(revenue_df['month'], revenue_df['revenue'],
        marker='o', label='Monthly Revenue', linewidth=2.5, color='#2E86AB', markersize=5)
ax1.plot(revenue_df['month'], revenue_df['revenue_ma3'],
        linestyle='--', label='3-Month Moving Avg', linewidth=2.5, color='#A23B72')

ax1.set_title('Revenue Growth Over Time', fontsize=18, fontweight='bold', pad=20)
ax1.set_xlabel('Month', fontsize=13)
ax1.set_ylabel('Revenue (R$)', fontsize=13)
ax1.legend(fontsize=11, loc='upper left')
ax1.grid(alpha=0.3, linestyle='--')
ax1.yaxis.set_major_formatter(plt.FuncFormatter(lambda x, p: f'R${x/1e6:.1f}M'))

# Subplot 2: Month-over-Month Growth Rate
revenue_clean = revenue_df[3:].copy()
revenue_clean = revenue_clean[revenue_clean['pct_change'].abs() < 200].copy()

revenue_clean = revenue_clean.reset_index(drop=True)
colors = []
for value in revenue_df['pct_change']:
    if value > 0:
        colors.append('#06D6A0')
    else:
        colors.append('#EF476F')
x = range(len(revenue_clean))
ax2.bar(x, revenue_clean['pct_change'], color=colors, alpha=0.7, edgecolor='black', width=0.6)
ax2.set_xticks(x)
ax2.set_xticklabels(pd.to_datetime(revenue_clean['month']).dt.strftime('%b %Y'), rotation=60, ha='right')
ax2.margins(x=0)
ax2.axhline(y=0, color='black', linestyle='-', linewidth=1)
ax2.set_ylim(-50, 150)
ax2.set_title('Month-over-Month Growth Rate', fontsize=16, fontweight='bold', pad=5)
ax2.set_xlabel('Month', fontsize=12)
ax2.set_ylabel('Growth Rate (%)', fontsize=12)
ax2.grid(alpha=0.3, linestyle='--', axis='y')

#plt.xticks(rotation=60, ha='right')
plt.tight_layout()
plt.savefig('01_revenue_trend.png', dpi=300, bbox_inches='tight')
plt.show()

#Insights
first_revenue = revenue_df['revenue'].iloc[0]
last_revenue = revenue_df['revenue'].iloc[-1]
total_growth = ((last_revenue / first_revenue) - 1) * 100
avg_mom_growth = revenue_clean['pct_change'].mean()

print(f"\n Revenue Growth Insights:")
print(f" First Month: R$ {first_revenue:,.2f}")
print(f" Last Month: R$ {last_revenue:,.2f}")
print(f" Total Growth: {total_growth:.1f}%")
print(f" Avg MoM Growth: {avg_mom_growth:.1f}%")
print(f" Highest Growth: {revenue_clean['pct_change'].max():.1f}%")
print(f" Lowest Growth: {revenue_clean['pct_change'].min():.1f}%")

#Viz2
query2 = """
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
"""

segment_df = pd.read_sql_query(query2, engine)

fig, axes = plt.subplots(1, 2, figsize=(16, 6))

# Plot 1: Customer Count by Segment
colors = ['#06D6A0', '#118AB2', '#073B4C', '#EF476F', '#FFD166', '#F78C6B', '#9B59B6', '#95A5A6']
bars = axes[0].barh(segment_df['customer_segment'], segment_df['customer_count'],
                    color=colors[:len(segment_df)], edgecolor='black', linewidth=1)
axes[0].set_xlabel('Number of Customers', fontsize=12)
axes[0].set_title('Customer Distribution by Segment', fontsize=14, fontweight='bold')
axes[0].grid(axis='x', alpha=0.3, linestyle='--')
axes[0].invert_yaxis()

# Add value labels
for i, (bar, count) in enumerate(zip(bars, segment_df['customer_count'])):
    width = bar.get_width()
    pct = (count / segment_df['customer_count'].sum()) * 100
    axes[0].text(width + 500, bar.get_y() + bar.get_height()/2,
                f'{int(count/1000)}K ({pct:.1f}%)',
                ha='left', va='center', fontsize=9, fontweight='bold')

# Plot 2: Average Lifetime Value by Segment
bars2 = axes[1].barh(segment_df['customer_segment'], segment_df['avg_lifetime_value'],
                     color=colors[:len(segment_df)], edgecolor='black', linewidth=1)
axes[1].set_xlabel('Average Lifetime Value (R$)', fontsize=12)
axes[1].set_title('Average CLV by Segment', fontsize=14, fontweight='bold')
axes[1].grid(axis='x', alpha=0.3, linestyle='--')
axes[1].invert_yaxis()

# Add value labels
for i, (bar, clv) in enumerate(zip(bars2, segment_df['avg_lifetime_value'])):
    width = bar.get_width()
    axes[1].text(width + 5, bar.get_y() + bar.get_height()/2,
                f'R${clv:.0f}',
                ha='left', va='center', fontsize=9, fontweight='bold')

plt.tight_layout()
plt.savefig('02_customer_segmentation.png', dpi=300, bbox_inches='tight')
plt.show()

print(f"\n Customer Segmentation Insights:")
print(segment_df[['customer_segment', 'customer_count', 'avg_lifetime_value']].to_string(index=False))

#Viz3
query3 = """
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
"""
category_df = pd.read_sql_query(query3, engine)

fig, ax = plt.subplots(figsize=(12, 8))
bars = ax.barh(category_df['category'], category_df['total_revenue']/1000,
              color='#06D6A0', edgecolor='black', linewidth=1)

ax.set_xlabel('Total Revenue (R$ Thousands)', fontsize=12)
ax.set_ylabel('Product Category', fontsize=12)
ax.set_title('Top 15 Categories by Revenue', fontsize=14, fontweight='bold')
ax.grid(axis='x', alpha=0.3, linestyle='--')
ax.invert_yaxis()

for i, (bar, revenue, score) in enumerate(zip(bars, category_df['total_revenue'], 
                                               category_df['avg_review_score'])):
    width = bar.get_width()
    ax.text(width + 10, bar.get_y() + bar.get_height()/2,
           f'R${revenue/1000:.0f}K ({score:.1f})',
           ha='left', va='center', fontsize=9)

plt.tight_layout()
plt.savefig('03_categories.png', dpi=300, bbox_inches='tight')
plt.show()

print(f"\n Category Performance:")
print(f"   Top: {category_df.iloc[0]['category']}")
print(f"   Revenue: R$ {category_df.iloc[0]['total_revenue']:,.2f}")

#Viz4
query4 = """
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
"""

clv_df = pd.read_sql_query(query4, engine)

fig, axes = plt.subplots(1, 2, figsize=(16, 6))

colors_pie = ['#EF476F', '#FFD166', '#06D6A0']
explode = (0.05, 0.05, 0.1)

axes[0].pie(clv_df['customer_count'], labels=clv_df['customer_type'], 
           autopct='%1.1f%%', colors=colors_pie, explode=explode,
           shadow=True, startangle=90, textprops={'fontsize': 11, 'fontweight': 'bold'})
axes[0].set_title('Customer Distribution', fontsize=14, fontweight='bold', pad=20)

axes[1].bar(clv_df['customer_type'], clv_df['avg_clv'],
           color=['#EF476F', '#FFD166', '#06D6A0'], 
           edgecolor='black', linewidth=1.5)
axes[1].set_ylabel('Average CLV (R$)', fontsize=12)
axes[1].set_title('Average CLV by Type', fontsize=14, fontweight='bold')
axes[1].grid(axis='y', alpha=0.3, linestyle='--')
axes[1].tick_params(axis='x', rotation=15)

for i, (x, y) in enumerate(zip(range(len(clv_df)), clv_df['avg_clv'])):
    axes[1].text(x, y + 5, f'R${y:.0f}', ha='center', va='bottom', 
                fontsize=10, fontweight='bold')

plt.tight_layout()
plt.savefig('04_clv.png', dpi=300, bbox_inches='tight')
plt.show()

print(f"\n CLV Insights:")
for _, row in clv_df.iterrows():
    pct = (row['customer_count'] / clv_df['customer_count'].sum()) * 100
    print(f"   {row['customer_type']}: {pct:.1f}% (R${row['avg_clv']:.2f})")

#Viz5
query5 = """
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
"""
delivery_df = pd.read_sql_query(query5, engine)
delivery_df['month'] = pd.to_datetime(delivery_df['month'])

fig, ax1 = plt.subplots(figsize=(14, 6))

color1 = '#118AB2'
ax1.set_xlabel('Month', fontsize=13)
ax1.set_ylabel('Average Delivery Days', color=color1, fontsize=13)
line1 = ax1.plot(delivery_df['month'], delivery_df['avg_delivery_days'], 
                 color=color1, marker='o', linewidth=2.5, label='Avg Delivery Days', markersize=6)
ax1.tick_params(axis='y', labelcolor=color1)
ax1.grid(alpha=0.3, linestyle='--')

ax2 = ax1.twinx()
color2 = '#EF476F'
ax2.set_ylabel('Late Delivery Rate (%)', color=color2, fontsize=13)
line2 = ax2.plot(delivery_df['month'], delivery_df['late_rate'], 
                 color=color2, marker='s', linewidth=2.5, linestyle='--', 
                 label='Late Delivery %', markersize=6)
ax2.tick_params(axis='y', labelcolor=color2)

lines = line1 + line2
labels = [l.get_label() for l in lines]
ax1.legend(lines, labels, loc='upper left', fontsize=11)

plt.title('Delivery Performance Over Time', fontsize=18, fontweight='bold', pad=20)
plt.xticks(rotation=45, ha='right')
fig.tight_layout()
plt.savefig('05_delivery_performance.png', dpi=300, bbox_inches='tight')
plt.show()

print(f"\n Delivery Performance:")
print(f"   Avg delivery time: {delivery_df['avg_delivery_days'].mean():.1f} days")
print(f"   Avg late rate: {delivery_df['late_rate'].mean():.1f}%")
