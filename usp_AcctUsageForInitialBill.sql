USE [finEnergyMgmt]
GO
/****** Object:  StoredProcedure [dbo].[usp_AcctUsageForInitialBill]    Script Date: 4/4/2014 10:35:42 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Feng Lu
-- Create date: 07/05/2012
-- Description:	Calculation for Initial
-- =============================================
ALTER PROCEDURE [dbo].[usp_AcctUsageForInitialBill]
 @year as int,
 @month as int
--set @month =5

--set @year=2011
AS
BEGIN

--- Check accounts change


declare @day as int
set @day=1
declare @mydate as datetime
--Set @mydate= dateadd(mm,(@year-1900)* 12 + @month - 1,0) + (@day-1) 
Set @mydate=convert(datetime, Convert(varchar,@month) + '-' + Convert(varchar,@day) + '-' + Convert(varchar,@year) ) ;
--print @mydate
--print dateadd(mm,1,@mydate)
--print dateadd(yy,-1,(dateadd(mm,1,@mydate)))  ;

With Pa as (
Select BILLING_AGENCY_CODE,ACCOUNT_NUMBER ,OGS_ZONE_ID, ACCOUNT_GO_LIVE_DATE, ACCOUNT_CANCEL_DATE  from dbo.ACCOUNT where 
 (ACCOUNT_GO_LIVE_DATE <dateadd(yy,-1,(dateadd(mm,1,@mydate)))  )  
-- and  
--(ACCOUNT_CANCEL_DATE is null or (Month(ACCOUNT_CANCEL_DATE) =@month and  Year(ACCOUNT_CANCEL_DATE)>=@year-1))

),
Ca as (
Select BILLING_AGENCY_CODE, ACCOUNT_NUMBER ,OGS_ZONE_ID, ACCOUNT_GO_LIVE_DATE, ACCOUNT_CANCEL_DATE  from dbo.ACCOUNT where 
 (ACCOUNT_GO_LIVE_DATE < dateadd(mm,1,@mydate)) 
  and  
   ( (ACCOUNT_CANCEL_DATE is null or (Month(ACCOUNT_CANCEL_DATE) =@month and  Year(ACCOUNT_CANCEL_DATE)=@year) 
   or  ACCOUNT_CANCEL_DATE>=@mydate )

)
),
 A as (
--- how many accts in prior year
Select * from Pa 
intersect
---how many accts in current month  dateadd(mm,@mydate,1)
Select * from Ca
),
F as (
------ Accts only on prior year List
--Select *,'Prior Year Only' as [Status] from Pa where ACCOUNT_NUMBER not in ( Select ACCOUNT_NUMBER from A) 
--union
--Select *, 'Both Years' as [Status] from A
--union
Select *,'Current Year Only' as [Status] from Ca 
where ACCOUNT_NUMBER not in ( Select ACCOUNT_NUMBER from A) ---- Accts only on current year List
),
--Select  * from F 

B as (
Select ACCOUNT_NUMBER, sum(Usage) as Usage from ACCOUNT_METERED_DATA
where month(date)=@month and year(date) =@year-1
 group by ACCOUNT_NUMBER
)
--Select * from B
,FF1 as (
Select BILLING_AGENCY_CODE,B.ACCOUNT_NUMBER, OGS_ZONE_ID,Usage,'Prior' as [status]
--,PEAK_INSTALLED_CAPACITY as ICAP_Initial
from B  Join A on B.ACCOUNT_NUMBER= A.ACCOUNT_NUMBER  
--Join ISO_PEAK on ISO_PEAK.ACCOUNT_ID= A.ACCOUNT_NUMBER 
--Where dateadd(yy,-1,@mydate) <=Date_end and dateadd(yy,-1,@mydate)>=Date_Start

union

Select BILLING_AGENCY_CODE,F.ACCOUNT_NUMBER, OGS_ZONE_ID,TOTAL_ORIG_METERED_USAGE ,[status]
--,I_TOTAL_PEAK_CAPACITY 
from F join dbo.COMPARISON_VALUES_BY_ACCOUNT on COMPARISON_VALUES_BY_ACCOUNT.ACCOUNT_ID=F.ACCOUNT_NUMBER
where COMPARISON_VALUES_BY_ACCOUNT.Month=@month and COMPARISON_VALUES_BY_ACCOUNT.Year=@year-1


)
,FF as (
Select distinct FF1.*, PEAK_INSTALLED_CAPACITY * isnull(P,1)  as ICAP_Initial,  isnull(P,1) as Per_ICAP from FF1 
Join ISO_PEAK on ISO_PEAK.ACCOUNT_ID= FF1.ACCOUNT_NUMBER 
left join fn_GetCapacityPercent(@mydate) as c on c.ACCOUNT_NUMBER=FF1.ACCOUNT_NUMBER
Where @mydate <=Date_end and @mydate >=Date_Start
--Where dateadd(yy,-1,@mydate) <=Date_end and dateadd(yy,-1,@mydate)>=Date_Start
)
,summary as (
Select  Account.DESCRIPTION ,FF.*,ISO_bill_Energy.Energy_Cost,
sum(usage) over(Partition By FF.OGS_Zone_ID) as 'Total Zone Usage',
round(usage/sum(usage) over(Partition By FF.OGS_Zone_ID),6) as 'Adjusted Percent Zone Usage',
sum(usage) over() as 'Total Usage', usage/ sum(usage) over () as 'Adjusted Percent Total Usage' ,
ISO_Bill_Other_Rates.ancillary_service, adjustment, installed_capacity 
 from FF Join account on account.ACCOUNT_NUMBER = FF.ACCOUNT_NUMBER
join ISO_bill_Energy on ISO_bill_Energy.ISO_Zone= FF.OGS_Zone_ID
Left Join ISO_Bill_Other_Rates on ISO_Bill_Other_Rates.month=ISO_bill_Energy.month and ISO_Bill_Other_Rates.year=ISO_bill_Energy.year and ISO_Bill_Other_Rates.Bill_Type=ISO_bill_Energy.Bill_type
where ISO_bill_Energy.Bill_Type='I' and ISO_bill_Energy.Year=@year and ISO_bill_Energy.month=@month
--order by FF.OGS_Zone_ID , [DESCRIPTION]
)
Select b.ISO_ZONE,a.*, [Adjusted Percent Total Usage]*ancillary_service as ancillary_service_1,ICAP_Initial/Sum(ICAP_Initial) over() as ICAPPercentage,
[Adjusted Percent Total Usage]*isnull(adjustment,0) as 'adjs', Energy_Cost *[Adjusted Percent Zone Usage]+ [Adjusted Percent Total Usage]*ancillary_service + [Adjusted Percent Total Usage]*adjustment + installed_capacity*ICAP_Initial/Sum(ICAP_Initial) over() as initialSettlement
 from summary as a  Join dbo.ZONE_TRANSLATION as b
on a.OGS_ZONE_ID = b.OGS_ZONE_ID
order by OGS_Zone_ID , [DESCRIPTION]


END
