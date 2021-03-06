USE [finEnergyMgmt]
GO
/****** Object:  StoredProcedure [dbo].[usp_4MonthOGSCostCal]    Script Date: 9/13/2016 9:43:12 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Feng Lu	
-- Create date: 5/23/2013
-- Description:	Calculation For 4 Month
-- =============================================
ALTER PROCEDURE [dbo].[usp_4MonthOGSCostCal]
	-- Add the parameters for the stored procedure here
@month int,
@year int

AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
--use [finEnergyMgmt]
--
--declare @year int
--declare @month int
--set @year =2011
--set @month = 1



Declare @mydate as datetime
Declare @NumOfDay as int
--Set @Month=5
--Set @Year=2011
Set @mydate=convert(datetime, Convert(varchar,@month) + '-' + Convert(varchar,1) + '-' + Convert(varchar,@year) ) ;
--Set @mydate=convert(datetime, Convert(varchar,5) + '-' + Convert(varchar,1) + '-' + Convert(varchar,2011) ) ;
Set @NumOfDay=  datediff(day, @mydate, dateadd(month, 1, @mydate))  --- Calculate how many days in that month
--print @NumOfDay;

declare @startdate  datetime
declare @enddate  datetime

if (@Month >=5)
begin

Set @startdate=convert(datetime, Convert(varchar,5) + '-' + Convert(varchar,1) + '-' + Convert(varchar,@year) ) ;
Set @enddate=convert(datetime, Convert(varchar,4) + '-' + Convert(varchar,30) + '-' + Convert(varchar,@year+1) ) ;

end
else

begin
Set @startdate=convert(datetime, Convert(varchar,5) + '-' + Convert(varchar,1) + '-' + Convert(varchar,@year-1) ) ;
Set @enddate=convert(datetime, Convert(varchar,4) + '-' + Convert(varchar,30) + '-' + Convert(varchar,@year) ) ;
end

;
declare @ancillary money
declare @adjust4Month money
declare @adjustInitial money
declare @ICAP money
declare @ICAP_OR money   ---- HUD_VL
Select @ancillary=ANCILLARY_SERVICE,
	   @adjust4Month = ADJUSTMENT,
	   @ICAP = INSTALLED_CAPACITY,
	   @ICAP_OR =isnull(INSTALLED_CAPACITY_OR,0)
 from  dbo.ISO_BILL_OTHER_RATES where BILL_TYPE ='4Month' and [year]=@year and [month]=@month

Select @adjustInitial= ADJUSTMENT from  dbo.ISO_BILL_OTHER_RATES
where BILL_TYPE ='I' and [year]=@year and [month]=@month

;
With a as (
Select ACCOUNT_NUMBER,[DATE],[HOUR], USAGE  from dbo.ACCOUNT_METERED_DATA
Where Year(DATE)=@Year and Month(DATE)=@Month 
and ACCOUNT_NUMBER in ( Select ACCOUNT_NUMBER from [dbo].[fn_GetAllActiveAcct](@year,@month))
--and ACCOUNT_NUMBER in ( Select ACCOUNT_ID from dbo.COMPARISON_VALUES_BY_ACCOUNT  Where [Year] =@Year and [Month]=@Month)
)
,b as (
Select a.*,b.SL,VOLTAGE_LEVEL,UTILITY_ID ,OGS_ZONE_ID,[DESCRIPTION],ACCOUNT_GO_LIVE_DATE from a 
left join (Select * from dbo.fn_SpecialLossFactor (@year,@month,@NumOfDay)) as b on a.ACCOUNT_NUMBER = b.ACCOUNT_NUMBER
join account on account.ACCOUNT_NUMBER = a.ACCOUNT_NUMBER 
where date >=ACCOUNT_GO_LIVE_DATE
)
,c as (
Select ACCOUNT_NUMBER, VOLTAGE_LEVEL,UTILITY_ID,[Date],[Hour],OGS_ZONE_ID,[DESCRIPTION],usage,ACCOUNT_GO_LIVE_DATE,
Case When SL is null then Usage 
else Usage * SL   --- Apply Special Loss Factors
end as UsageWithSpecialFactors
from b )
,d as (
Select distinct C.*,ADJUSTMENT_FACTOR,ADJUSTMENT_FACTOR *UsageWithSpecialFactors as UsageWithStandardFactor  from c join  --- Apply Standard Loss Factor
dbo.SERVICE_CLASS_CALCULATION_FACTOR as d1 on c.UTILITY_ID=d1.UTILITY_ID and c.VOLTAGE_LEVEL=d1.VOLTAGE_LEVEL
Where [Year]=@Year and [Month]=@Month 

)

,e as (
Select  *,UsageWithStandardFactor * (1 + dbo.fn_NationaGridUFE(@year,@month)) as UsageWithUFE 
from d where UTILITY_ID=1 

union
Select    d.*,
case when totalHourlyZoneUsage <>0 then
UsageWithStandardFactor + (UsageWithStandardFactor/totalHourlyZoneUsage) * UFE_KWH * 1000  
end 
as UsageWithUFE
 from  d
  Join dbo.fn_TotalHourlyZoneUsage(@year,@month,2) as e 
on d.utility_id=e.utility_id and d.hour=e.hour and d.date = e.date and e.OGS_ZONE_ID=d.OGS_ZONE_ID and d.ACCOUNT_NUMBER=e.ACCOUNT_NUMBER
where d.utility_id=2  

union
Select    d.*,
case when totalHourlyZoneUsage <>0 then
UsageWithStandardFactor + (UsageWithStandardFactor/totalHourlyZoneUsage) * UFE_KWH * 1000  
end 
as UsageWithUFE
 from  d
  Join dbo.fn_TotalHourlyZoneUsage(@year,@month,3) as e 
on d.utility_id=e.utility_id and d.hour=e.hour and d.date = e.date and e.OGS_ZONE_ID=d.OGS_ZONE_ID and d.ACCOUNT_NUMBER=e.ACCOUNT_NUMBER
where d.utility_id=3  

union
Select    d.*,
case when totalHourlyZoneUsage <>0 then
UsageWithStandardFactor + (UsageWithStandardFactor/totalHourlyZoneUsage) * UFE_KWH * 1000  
end 
as UsageWithUFE
 from  d
  Join dbo.fn_TotalHourlyZoneUsage(@year,@month,4) as e 
on d.utility_id=e.utility_id and d.hour=e.hour and d.date = e.date and e.OGS_ZONE_ID=d.OGS_ZONE_ID and d.ACCOUNT_NUMBER=e.ACCOUNT_NUMBER
where d.utility_id=4 

)
--,f as (
--Select distinct [DESCRIPTION], ACCOUNT_NUMBER, e.OGS_ZONE_ID,ISO_ZONE, round(sum(UsageWithUFE) over (partition by ACCOUNT_NUMBER),2) as AdjustedTotal
-- from e join
--dbo.ZONE_TRANSLATION as Z on e.OGS_ZONE_ID= Z.OGS_ZONE_ID)

,Pre_ICAP as (
-- each utility
Select Account_ID,Peak_installed_capacity, ICAPGroup  from dbo.fn_GetPeakCapacity(@year,@month,1,@startdate,@enddate,1)
union
Select Account_ID,Peak_installed_capacity, ICAPGroup from dbo.fn_GetPeakCapacity(@year,@month,2,@startdate,@enddate,1)
union
Select Account_ID,Peak_installed_capacity , ICAPGroup from dbo.fn_GetPeakCapacity(@year,@month,3,@startdate,@enddate,1)
union
Select Account_ID,Peak_installed_capacity , ICAPGroup from dbo.fn_GetPeakCapacity(@year,@month,4,@startdate,@enddate,1)
)
,ICAP as (
Select Account_ID,ICAPGroup, Peak_installed_capacity * isnull(P,1) as Peak_installed_capacity from Pre_ICAP
Left Join dbo.fn_GetCapacityPercent (@mydate) as fn on fn.ACCOUNT_NUMBER=Pre_ICAP.Account_ID
)
,adjusage as ( ---Get Cost by OGS Rate times Adjuested Usage
Select e.*,Zonal_LBMP, round(usagewithUFE*Zonal_LBMP,2) as Cost  from e 
join dbo.SUBZONE on e.UTILITY_ID =  SUBZONE.utility and (SUBZONE.Description LIKE 'NYISO%')and e.OGS_Zone_ID=SUBZONE.Zone_ID
Join dbo.ISO_OGS_HOURLY_RATES as ORate
on e.hour=oRate.hour and e.date=ORate.date and ORate.SubZone_ID=SUBZONE.SUbZone_ID
--and  e.OGS_Zone_ID= ORate.Zone_ID and =ORate.utility
where year(e.DATE)=@year and month(e.date)=@month 
)
,f as (
--Get Adjusted Usage and overall percentage
Select distinct OGS_ZONE_ID,[Description], Account_Number,round(sum(UsageWithUFE) over (Partition by Account_Number)/1000,3)  as Tusage,
round(sum(UsageWithUFE) over (Partition by Account_Number) /sum(UsageWithUFE) over(),8) as usagePercental,
sum(Cost) over (Partition by Account_Number)/1000 as TCost  from adjusage
) 
, final as (
Select f.*,Peak_installed_capacity, 
@ancillary * usagePercental as '4monthAncillary' ,
 @adjust4Month *usagePercental as '4MonthAdjust' ,
@adjustInitial * usagePercental as 'InitialAdjust',
case when ICAPGroup =1 then
@ICAP * Peak_installed_capacity/sum(Peak_installed_capacity) over(Partition by ICAPGroup)
when ICAPGroup =2  then
@ICAP_OR * Peak_installed_capacity/sum(Peak_installed_capacity) over(Partition by ICAPGroup)
  end as '4MonthICAP' ,
sum(Tusage) over (Partition by OGS_Zone_ID) as UsageZoneTotal,
sum(TCost) over (Partition by OGS_Zone_ID) as CostZoneTotal,
I_ENERGY_COST,energy_cost, ICAPGroup,
Peak_installed_capacity/sum(Peak_installed_capacity) over( Partition by ICAPGroup ) as ICAPPercental 

 from f
Join ICAP on f.Account_Number = ICAP.Account_ID
Join COMPARISON_VALUES_BY_ACCOUNT as comp on comp.Account_ID=f.Account_Number and comp.year=@year and comp.month=@month
Join ISO_BILL_ENERGY as Bill on bill.Bill_type='4Month' and bill.ISO_ZONE=f.ogs_zone_id and bill.year=@year and bill.month=@month
)

Select *, (energy_cost-CostZoneTotal)*(Tusage/UsageZoneTotal) as dist  from final
order by OGS_ZONE_ID,[Description]




END

