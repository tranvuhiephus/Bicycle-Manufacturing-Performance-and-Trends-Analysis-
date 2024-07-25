

/* Bicycle-Manufacturing-Performance-and-Trends-Analysis-*/


--Task 1: Calc Quantity of items, Sales value & Order quantity by each Subcategory in L12M

SELECT DISTINCT 
    FORMAT_DATETIME("%b %Y", t1.ModifiedDate) AS period,
    t3.Name AS Name,
    SUM(t1.OrderQty) AS qty_item,
    SUM(t1.LineTotal) AS sales_value,
    COUNT(DISTINCT t1.SalesOrderID) AS order_cnt
FROM 
    `adventureworks2019.Sales.SalesOrderDetail` t1
LEFT JOIN 
    `adventureworks2019.Production.Product` t2 ON t1.ProductID = t2.ProductID
LEFT JOIN 
    `adventureworks2019.Production.ProductSubcategory` t3 ON CAST(t2.ProductSubcategoryID AS INT64) = t3.ProductSubcategoryID
WHERE 
  date(t1.ModifiedDate) between (date_sub(date(t1.ModifiedDate), INTERVAL 12 month)) and '2014-06-30'
GROUP BY 
    period, Name
ORDER BY 
    period DESC, name ASC  ;


--Task 2: Calc % YoY growth rate by SubCategory & release top 3 cat with highest grow rate. Can use metric: quantity_item. Round results to 2 decimal

WITH 
sale_info AS (
  SELECT 
      FORMAT_TIMESTAMP("%Y", a.ModifiedDate) AS yr,
      c.Name,
      SUM(a.OrderQty) AS qty_item
  FROM `adventureworks2019.Sales.SalesOrderDetail` a 
  LEFT JOIN `adventureworks2019.Production.Product` b ON a.ProductID = b.ProductID
  LEFT JOIN `adventureworks2019.Production.ProductSubcategory` c ON CAST(b.ProductSubcategoryID AS INT) = c.ProductSubcategoryID
  GROUP BY 1, 2
  ORDER BY 2 ASC, 1 DESC
),
sale_diff AS (
  SELECT *,
         LEAD(qty_item) OVER (PARTITION BY Name ORDER BY yr DESC) AS prv_qty,
         ROUND(qty_item / (LEAD(qty_item) OVER (PARTITION BY Name ORDER BY yr DESC)) - 1, 2) AS qty_diff
  FROM sale_info
),
rk_qty_diff AS (
  SELECT *,
         DENSE_RANK() OVER (ORDER BY qty_diff DESC) AS dk
  FROM sale_diff
)

SELECT Name,
       qty_item,
       prv_qty,
       qty_diff
FROM (
  SELECT DISTINCT Name,
                  qty_item,
                  prv_qty,
                  qty_diff,
                  dk
  FROM rk_qty_diff 
  WHERE dk <= 3
) sub
ORDER BY dk ASC, qty_diff DESC;



--Task 3: Ranking Top 3 TeritoryID with biggest Order quantity of every year. If there's TerritoryID with same quantity in a year, do not skip the rank number


WITH total_order_territoryID AS(
    SELECT 
        FORMAT_DATE('%Y', t2.ModifiedDate) yr
        ,t2.TerritoryID AS Territory_id
        ,SUM(t1.OrderQty) order_cnt

    FROM 
        `adventureworks2019.Sales.SalesOrderDetail` t1
    LEFT JOIN 
        `adventureworks2019.Sales.SalesOrderHeader` t2 ON t1.SalesOrderID =  t2.SalesOrderID
    GROUP BY 
        yr, Territory_id
)
,full_territory AS(
    SELECT
        DISTINCT yr
        ,Territory_id
        ,order_cnt
        ,DENSE_RANK() OVER( PARTITION BY yr ORDER BY order_cnt DESC) rankking
    FROM 
        total_order_territoryID
)
SELECT *
FROM full_territory
WHERE rankking <= 3
ORDER BY yr DESC , rankking ASC;




--Task 4: Calc Total Discount Cost belongs to Seasonal Discount for each SubCategory

SELECT 
    FORMAT_TIMESTAMP("%Y", ModifiedDate) AS year,
    Name,
    SUM(disc_cost) AS total_cost
FROM (
    SELECT DISTINCT
        a.SalesOrderID, a.ProductID, a.SpecialOfferID, a.OrderQty, a.UnitPrice, a.ModifiedDate,
        c.Name,
        d.DiscountPct, d.Type,
        a.OrderQty * d.DiscountPct * a.UnitPrice AS disc_cost 
    FROM `adventureworks2019.Sales.SalesOrderDetail` a
    LEFT JOIN `adventureworks2019.Production.Product` b ON a.ProductID = b.ProductID
    LEFT JOIN `adventureworks2019.Production.ProductSubcategory` c ON CAST(b.ProductSubcategoryID AS INT) = c.ProductSubcategoryID
    LEFT JOIN `adventureworks2019.Sales.SpecialOffer` d ON a.SpecialOfferID = d.SpecialOfferID
    WHERE LOWER(d.Type) LIKE '%seasonal discount%' 
)
GROUP BY year, Name
ORDER BY year, Name;



--Task 5: Retention rate of Customer in 2014 with status of Successfully Shipped (Cohort Analysis)

/*
summary: tính toán tỉ lệ giữ chân khách hàng(hiểu là mua lần đầu tiên thành công rồi mua tiếp)
        tỉ lệ này được tính bằng cách nhóm các cus thành các nhóm dựa trên tháng đầu tiên mà họ giao dịch,
        rồi sau đó tính số lựng khách hàng trong mỗi nhóm qua các tháng tiếp theo */

WITH 
info AS (
  SELECT  
      EXTRACT(MONTH FROM ModifiedDate) AS month_no,
      EXTRACT(YEAR FROM ModifiedDate) AS year_no,
      CustomerID,
      COUNT(DISTINCT SalesOrderID) AS order_cnt
  FROM `adventureworks2019.Sales.SalesOrderHeader`
  WHERE FORMAT_TIMESTAMP("%Y", ModifiedDate) = '2014'
  AND Status = 5
  GROUP BY 
      EXTRACT(MONTH FROM ModifiedDate),
      EXTRACT(YEAR FROM ModifiedDate),
      CustomerID
),
row_num AS (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY month_no) AS row_numb
  FROM info 
), 
first_order AS (
  SELECT *
  FROM row_num
  WHERE row_numb = 1 
), 
month_gap AS (
  SELECT 
      a.CustomerID,
      b.month_no AS month_join,
      a.month_no AS month_order,
      a.order_cnt,
      CONCAT('M - ', a.month_no - b.month_no) AS month_diff
  FROM info a 
  LEFT JOIN first_order b 
  ON a.CustomerID = b.CustomerID
)
SELECT 
    month_join,
    month_diff,
    COUNT(DISTINCT CustomerID) AS customer_cnt
FROM month_gap
GROUP BY 
    month_join,
    month_diff
ORDER BY 
    month_join ASC,
    month_diff ASC;




--Task 6: Trend of Stock level & MoM diff % by all product in 2011. If %gr rate is null then 0. Round to 1 decimal

/*Xu hướng tồn kho và chênh lệch % theo tháng của tất cả sản phẩm trong năm 2011. 
Tỷ lệ %gr bằng 0 thì làm tròn đến 1 thập phân*/


WITH Stock_level AS (
    SELECT  
         p.Name
        ,FORMAT_DATE('%m', w.ModifiedDate) mth
        ,FORMAT_DATE('%Y', w.ModifiedDate) yr
        ,SUM(w.StockedQty) Stock_current
    FROM 
        `adventureworks2019.Production.Product` p
    LEFT JOIN 
        `adventureworks2019.Production.WorkOrder` w ON p.ProductID = w.ProductID
    WHERE 
        EXTRACT(YEAR FROM w.ModifiedDate) = 2011
    GROUP BY 
        Name, mth, yr
)

SELECT  
    Name,
    mth,
    yr,
    Stock_current,
    ROUND(COALESCE((100.0 * (Stock_current - LAG(Stock_current, 1) OVER (PARTITION BY Name ORDER BY yr, mth)) 
            / LAG(Stock_current, 1) OVER (PARTITION BY Name ORDER BY yr, mth)), 0), 1) AS MoM_diff_pct
FROM 
    Stock_level
ORDER BY 
    Name ASC, yr DESC, mth DESC;

--Task 7: Calc Ratio of Stock / Sales in 2011 by product name, by month. Order results by month desc, ratio desc. Round Ratio to 1 decimal


WITH sale_info AS (
    SELECT  
        a.ProductID,
        FORMAT_DATE('%m', a.ModifiedDate) Month,
        FORMAT_DATE('%Y', a.ModifiedDate) Year,
        COALESCE(SUM(a.OrderQty), 0) sales_amount
    FROM 
        `adventureworks2019.Sales.SalesOrderDetail` a 
    LEFT JOIN 
        `adventureworks2019.Production.Product` b ON a.ProductID = b.ProductID
    GROUP BY 
        a.ProductID, Month, Year
),
stock_info AS (
    SELECT  
        ProductID,
        FORMAT_DATE('%m', ModifiedDate) Month,
        FORMAT_DATE('%Y', ModifiedDate) Year,
        COALESCE(SUM(StockedQty), 0) Stocks_amount
    FROM 
        `adventureworks2019.Production.WorkOrder`
    GROUP BY 
        ProductID, Month, Year
)

SELECT  
     s.Month
    ,s.Year
    ,COALESCE((SELECT Name FROM `adventureworks2019.Production.Product` b WHERE b.ProductID = s.ProductID), 'Unknown') AS ProductName

    ,ROUND(COALESCE(s.sales_amount, 0), 1) Sales_cnt
    ,ROUND(COALESCE(w.stocks_amount, 0), 1) Stock_cnt
    ,ROUND(COALESCE(w.stocks_amount / s.sales_amount, 0), 1) ratio
FROM 
    sale_info s
JOIN 
    stock_info w ON s.ProductID = w.ProductID AND s.Month = w.Month AND s.Year = w.Year
WHERE 
    s.Year = '2011'
ORDER BY 
    s.Year DESC, s.Month DESC, ratio DESC;


--Task 8: No of order and value at Pending status in 2014


SELECT 
     FORMAT_DATE('%Y', ModifiedDate) yr
    ,COUNT(DISTINCT PurchaseOrderID) order_cnt
    ,SUM(TotalDue) sum_value
FROM `adventureworks2019.Purchasing.PurchaseOrderHeader`
WHERE
    EXTRACT(YEAR FROM ModifiedDate) = 2014
    AND Status = 1
GROUP BY yr;

                                                



