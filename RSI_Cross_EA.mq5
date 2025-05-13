//+------------------------------------------------------------------+
//| RSI Reversal Expert Advisor                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

// Include required files
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

// Create objects for trading
CTrade trade;
CPositionInfo positionInfo;
CSymbolInfo symbolInfo;

// Color definitions
color Gray1 = clrSilver;

// Global variables
datetime time_start_buy = 0;
datetime time_start_sell = 0;
int SpeedEA = 1;
bool Info = true;

string error_message_buy = "";
string sell_order_symbol = "";
string sell_order_info = "";
string error_message_sell = "";
string buy_stop_order_log = "";
string sell_stop_order_log = "";

// RSI Settings
input int RSI_Period = 14;        // RSI Period
input int RSI_UpperLevel = 70;    // RSI Upper Level
input int RSI_LowerLevel = 30;    // RSI Lower Level
input int RSI_TPLevel = 50;       // RSI Take Profit Level
input double MinProfit = 15;      // Minimum Profit in Pips

// Lot Settings
enum LotAss
{
   Fixed = 0,       // Fixed lot assignment
   AutoMM = 1,      // Automatic Money Management (percentage risk)
   BalanceRatio = 2 // Balance-to-lot ratio
};

input int MagicNumber = 54785;                // Magic Number
input string s3 = "------------ Strategy Settings ----------------"; // Section header for strategy settings
input double FixedLots = 0.1;                 // Fixed lot size
input string PercentageRiskSettings = "***************************"; // Placeholder string for risk settings
input double PercentageRisk = 0.1;            // Percentage of account balance to risk
input int PercentageRiskBasedOnPointsMovement = 100; // Points movement for risk calculation
input string BalanceRatioSettings = "***************************";   // Placeholder string for balance ratio settings
input double ForEvery = 1000;                 // Balance increment for lot calculation
input double UseLotsForEveryBalance = 0.1;    // Lot size for every balance increment
input string LotsSelection = "***************************";          // Placeholder string for lot selection
input LotAss LotAssignment = Fixed;           // Lot assignment method (Fixed by default)

// MA Filter Settings
input bool UseMA200Filter = true;             // Use MA200 Filter
input ENUM_MA_METHOD MA_Method = MODE_SMA;    // MA Method

// Trading Settings
input bool AutoTPTralBySymbol = true;         // Enable automatic TP/Tral/TralStart adaptation by symbol
input int TakeProfit = 30;                    // Take profit in pips
input double Tral = 20;                       // Trailing stop in pips
input double TralStart = 10;                  // Start trailing when profit exceeds 5 pips

input string s4d = "------------ Stop Loss  ----------------"; // Section header for stop loss settings
input bool UseStopLoss = false;
input int StopLoss = 500;

input double MaxSpread = 40;                  // Maximum spread allowed for trade execution
input double PipsStep = 1;                    // Pip step for trailing stop or entry
input int OpenTime = 1;                       // Time to keep trade open (in hours)

input string s4 = "------------ Options ----------------"; // Section header for options
input string trading_system_name;             // Name or comment for the trading system

enum point_type
{
   point_type_point,
   point_type_pips,
};

input point_type PointType = point_type_point; // Choose between points or pips for calculations

input string s35d = "----------- RSI Filter ----------------"; // Section header for RSI filter
input bool UseRSIFilter = true;               // Enable or disable RSI filter
input ENUM_TIMEFRAMES RSIFilter_TF = PERIOD_CURRENT; // Timeframe for RSI filter
input int Filter_RSI_Period = 14;             // RSI period for filter
input double Filter_StopBuyAboveRSI = 30;     // Do not buy if RSI is above this value
input double Filter_StopBuyBelow = 0;         // Do not buy if RSI is below this value
input double Filter_StopSellAboveRSI = 100;   // Do not sell if RSI is above this value
input double Filter_StopSellBelow = 70;       // Do not sell if RSI is below this value

input string s5 = "------------ Trading Hours ----------------"; // Section header for trading hours
input int TimeStart_Hour = 0;                 // Trading start hour (0-23)
input int TimeStart_Minute = 0;               // Trading start minute (0-59)
input int TimeEnd_Hour = 24;                  // Trading end hour (0-23)
input int TimeEnd_Minute = 0;                 // Trading end minute (0-59)

input string s13 = "------------ Max Orders      ----------------"; // Section header for max orders
input int MaxOrdersBuy = 30;                  // Maximum number of buy orders allowed
input int MaxOrdersSell = 30;                 // Maximum number of sell orders allowed

enum dir
{
   dir_both,  // BUY&SELL
   dir_buy,   // ONLY BUY
   dir_sell   // ONLY SELL
};

input dir Direction = dir_both;               // Trading direction: both, buy only, or sell only

enum tar
{
   tar_both,  // BUY&SELL
   tar_only,  // BUY OR SELL
};

input tar TakeProfitMode = tar_only;          // Mode de gestion du profit : séparé (défaut) ou groupé

// Global variables for trading
bool rsi_buy;
bool rsi_sell;
datetime TimeFlag = 1;
string str_symb_prop = "";

// RSI and MA handles
int rsiHandle;
int maHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trading objects
   trade.SetExpertMagicNumber(MagicNumber);
   symbolInfo.Name(_Symbol);
   
   // Initialize RSI
   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE)
   {
      Print("Error creating RSI indicator");
      return(INIT_FAILED);
   }
   
   // Initialize MA200 if filter is enabled
   if(UseMA200Filter)
   {
      maHandle = iMA(_Symbol, PERIOD_CURRENT, 200, 0, MA_Method, PRICE_CLOSE);
      if(maHandle == INVALID_HANDLE)
      {
         Print("Error creating MA indicator");
         return(INIT_FAILED);
      }
   }
   
   // Set up the EA
   Print("ID " + IntegerToString((int)TimeCurrent()));
   str_symb_prop = SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   
   // Set timer for EA speed control
   EventSetMillisecondTimer(SpeedEA);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, 23);
   ObjectsDeleteAll(0, 28);
   ObjectsDeleteAll(0, "ma_filter");
   
   // Release indicator handles
   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
   if(UseMA200Filter && maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update symbol info
   symbolInfo.RefreshRates();
   
   // Check if we can trade
   if(!symbolInfo.IsSynchronized())
      return;
      
   // Get current spread
   double current_spread = symbolInfo.Ask() - symbolInfo.Bid();
   double spread_in_points = current_spread / _Point;
   
   // Check spread
   if(MaxSpread > 0 && spread_in_points > MaxSpread)
      return;
      
   // Check trading hours
   if(!IsTradeAllowed())
      return;
      
   // Get RSI values
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) != 3)
   {
      Print("Error copying RSI buffer");
      return;
   }
   
   // Get MA value if filter is enabled
   double maBuffer[];
   bool maFilterBuy = true;
   bool maFilterSell = true;
   
   if(UseMA200Filter)
   {
      ArraySetAsSeries(maBuffer, true);
      if(CopyBuffer(maHandle, 0, 0, 1, maBuffer) != 1)
      {
         Print("Error copying MA buffer");
         return;
      }
      maFilterBuy = symbolInfo.Bid() > maBuffer[0];
      maFilterSell = symbolInfo.Ask() < maBuffer[0];
   }
   
   // Check RSI conditions
   if(UseRSIFilter)
   {
      rsi_buy = (rsiBuffer[0] <= Filter_StopBuyAboveRSI && rsiBuffer[0] >= Filter_StopBuyBelow) && maFilterBuy;
      rsi_sell = (rsiBuffer[0] >= Filter_StopSellBelow && rsiBuffer[0] <= Filter_StopSellAboveRSI) && maFilterSell;
   }
   else
   {
      rsi_buy = maFilterBuy;
      rsi_sell = maFilterSell;
   }
   
   // Process trading logic
   ProcessTrading(rsiBuffer[0]);
   
   // Apply trailing stop
   ApplyTrailingStop();
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   OnTick();
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
   datetime current_time = TimeCurrent();
   MqlDateTime time_struct;
   TimeToStruct(current_time, time_struct);
   
   int current_hour = time_struct.hour;
   int current_minute = time_struct.min;
   
   int current_time_minutes = current_hour * 60 + current_minute;
   int start_time_minutes = TimeStart_Hour * 60 + TimeStart_Minute;
   int end_time_minutes = TimeEnd_Hour * 60 + TimeEnd_Minute;
   
   if(end_time_minutes <= start_time_minutes)
      end_time_minutes += 24 * 60;
      
   if(current_time_minutes < start_time_minutes)
      current_time_minutes += 24 * 60;
      
   return (current_time_minutes >= start_time_minutes && current_time_minutes <= end_time_minutes);
}

//+------------------------------------------------------------------+
//| Process trading logic                                            |
//+------------------------------------------------------------------+
void ProcessTrading(double currentRSI)
{
   // Count current positions
   int buy_count = CountPositions(POSITION_TYPE_BUY);
   int sell_count = CountPositions(POSITION_TYPE_SELL);
   
   // Process buy orders
   if(buy_count < MaxOrdersBuy && rsi_buy && (Direction == dir_both || Direction == dir_buy))
   {
      // Check RSI crossing above lower level
      if(currentRSI > RSI_LowerLevel)
      {
         double lot_size = CalculateLotSize();
         if(lot_size > 0)
         {
            double sl = UseStopLoss ? symbolInfo.Bid() - StopLoss * _Point : 0;
            double tp = TakeProfit > 0 ? symbolInfo.Ask() + TakeProfit * _Point : 0;
            
            trade.Buy(lot_size, _Symbol, symbolInfo.Ask(), sl, tp, trading_system_name);
         }
      }
   }
   
   // Process sell orders
   if(sell_count < MaxOrdersSell && rsi_sell && (Direction == dir_both || Direction == dir_sell))
   {
      // Check RSI crossing below upper level
      if(currentRSI < RSI_UpperLevel)
      {
         double lot_size = CalculateLotSize();
         if(lot_size > 0)
         {
            double sl = UseStopLoss ? symbolInfo.Ask() + StopLoss * _Point : 0;
            double tp = TakeProfit > 0 ? symbolInfo.Bid() - TakeProfit * _Point : 0;
            
            trade.Sell(lot_size, _Symbol, symbolInfo.Bid(), sl, tp, trading_system_name);
         }
      }
   }
   
   // Check take profit conditions
   CheckTakeProfit(currentRSI);
}

//+------------------------------------------------------------------+
//| Count positions of specified type                                |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE pos_type)
{
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && 
            positionInfo.Magic() == MagicNumber && 
            positionInfo.PositionType() == pos_type)
         {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on selected method                      |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double lot_size = FixedLots;
   
   if(LotAssignment == AutoMM)
   {
      double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * PercentageRisk;
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      lot_size = risk_amount / (PercentageRiskBasedOnPointsMovement * tick_value);
   }
   else if(LotAssignment == BalanceRatio)
   {
      double balance_ratio = MathFloor(AccountInfoDouble(ACCOUNT_BALANCE) / ForEvery);
      lot_size = balance_ratio * UseLotsForEveryBalance;
   }
   
   // Normalize lot size
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot_size = MathFloor(lot_size / lot_step) * lot_step;
   lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
   
   return lot_size;
}

//+------------------------------------------------------------------+
//| Check take profit conditions                                     |
//+------------------------------------------------------------------+
void CheckTakeProfit(double currentRSI)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
         {
            double positionProfit = positionInfo.Profit();
            
            if(positionInfo.PositionType() == POSITION_TYPE_BUY)
            {
               if(currentRSI >= RSI_TPLevel && positionProfit >= MinProfit * _Point)
               {
                  trade.PositionClose(positionInfo.Ticket());
               }
            }
            else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
            {
               if(currentRSI <= RSI_TPLevel && positionProfit >= MinProfit * _Point)
               {
                  trade.PositionClose(positionInfo.Ticket());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Apply trailing stop to positions                                 |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   if(Tral <= 0)
      return;
      
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
         {
            double current_sl = positionInfo.StopLoss();
            double open_price = positionInfo.PriceOpen();
            double current_price = positionInfo.PriceCurrent();
            
            if(positionInfo.PositionType() == POSITION_TYPE_BUY)
            {
               if(current_sl < open_price || current_sl == 0)
               {
                  if(current_price - open_price >= TralStart * _Point)
                  {
                     double new_sl = current_price - Tral * _Point;
                     if(new_sl > current_sl)
                     {
                        trade.PositionModify(positionInfo.Ticket(), new_sl, positionInfo.TakeProfit());
                     }
                  }
               }
            }
            else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
            {
               if(current_sl > open_price || current_sl == 0)
               {
                  if(open_price - current_price >= TralStart * _Point)
                  {
                     double new_sl = current_price + Tral * _Point;
                     if(new_sl < current_sl || current_sl == 0)
                     {
                        trade.PositionModify(positionInfo.Ticket(), new_sl, positionInfo.TakeProfit());
                     }
                  }
               }
            }
         }
      }
   }
} 