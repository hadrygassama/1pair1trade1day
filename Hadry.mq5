//+------------------------------------------------------------------+
//|                                                           RsiCanBeProfitable.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// Trading direction
enum ENUM_TRADE_DIRECTION {
   TRADE_BUY_ONLY,      // Buy Only
   TRADE_SELL_ONLY,     // Sell Only
   TRADE_BOTH           // Buy and Sell
};

// RSI Trading Mode
enum ENUM_RSI_MODE {
   RSI_REVERSAL,      // RSI Reversal Strategy
   RSI_CONTINUATION   // RSI Continuation Strategy
};

// Forex pairs to trade
string ForexPairs[];

// Variables globales pour la gestion des logs
static datetime lastLogTime = 0;
static const int MIN_LOG_INTERVAL = 30; // 30 secondes entre les logs similaires
static double lastLoggedPrice = 0;      // Pour suivre le dernier prix logué
static const double PRICE_CHANGE_THRESHOLD = 0.5; // Minimum 0.5 pips de changement pour reloger

// Structure pour stocker les données par paire
struct SymbolData {
   string symbol;
   double lastBidPrice;
   double totalPriceMovement;
   datetime lastPositionTime;
   datetime lastPriceDirectionChange;
   double lastPriceDirection;
   double lastSignificantBid;
   datetime lastOpenTime;
   datetime lastDCAEntryTime;
   double maxBuyDD;
   double maxSellDD;
   double maxTotalDD;
   double initialBalance;
   double dailyProfitTarget;
   datetime lastDailyReset;
   double currentProfit;    // Current open positions profit
   double totalProfit;      // Total profit including closed trades
};

// Tableau pour stocker les données de chaque paire
SymbolData symbolData[];

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Trading Direction Settings ==="
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Direction
input int      Magic = 123456;              // Magic number for trade identification
input string   ExpertName = "RsiCanBeProfitable";       // Expert Advisor name for trade comments

input group "=== Position Management Settings ==="
input double   Lots = 0.25;                 // Trading volume in lots
input int      OpenTime = 30;               // Minimum seconds between opening new positions
input int      TimeStart = 0;               // Trading start hour (0-23)
input int      TimeEnd = 23;                // Trading end hour (0-23)
input double   MaxSpread = 40;              // Maximum allowed spread in pips
input double   PipsStep = 25;               // Distance in pips to open next position
input double   MinTradeDistance = 15;       // Minimum distance in pips between trades
input int      MinTradeInterval = 2;        // Minimum bars between trades in same direction

input group "=== Stop Loss and Take Profit Settings ==="
input int      Tral = 5;                    // Trailing stop distance in pips
input int      TralStart = 20;              // Profit in pips to start trailing stop
input double   TakeProfit = 35.0;           // Take profit level in pips
input double   DailyProfitTarget = 1.0;     // Daily profit target in % of balance
input double   ProfitTargetAmount = 1000.0;  // Profit target amount in USD to close all positions

input group "=== Display Settings ==="
input bool     Info = true;                 // Show information panel
input int      FontSize = 12;               // Font size for information panel
input color    TextColor = clrWhite;        // Text color for information panel
input int      PanelWidth = 400;            // Width of information panel
input int      PanelHeight = 500;           // Height of information panel
input int      PanelMargin = 10;            // Margin around information panel
input int      PanelBorderSize = 2;         // Border size of information panel
input int      MaxVisiblePairs = 10;        // Maximum number of pairs to show before scrolling

input group "=== Price Movement Settings ==="
input int      MovementResetTime = 300;     // Seconds before resetting price movement
input double   MinMovementThreshold = 1.0;  // Minimum price movement to consider
input double   DirectionChangeThreshold = 10; // Pips needed to change price direction

input group "=== DCA Settings ==="
input int      DCAMinDelay = 60;            // Minimum seconds between DCA positions
input double   SpreadWarningThreshold = 45.0; // Spread level to show warning

input group "=== RSI Settings ==="
input ENUM_RSI_MODE RsiMode = RSI_REVERSAL;  // RSI Trading Mode
input int      RsiPeriod = 14;               // RSI Period
input int      RsiOverbought = 70;           // RSI Overbought Level
input int      RsiOversold = 30;             // RSI Oversold Level

input group "=== Forex Pairs Settings ==="
input string   ForexPairsList = "EURUSD,GBPUSD,USDJPY,EURJPY,GBPJPY,EURGBP,USDCHF,EURCHF,AUDUSD,USDCAD";  // Forex pairs to trade (comma separated)

// Global variables
CTrade trade;
string expertName = ExpertName;
datetime lastOpenTime = 0;
double lastBidPrice = 0;
double globalInitialBalance = 0;  // Renamed from initialBalance
double maxBuyDD = 0;
double maxSellDD = 0;
double maxTotalDD = 0;
double totalPriceMovement = 0;
datetime lastPositionTime = 0;
datetime lastPriceDirectionChange = 0;
double lastPriceDirection = 0;
double lastSignificantBid = 0;
datetime lastCloseTime = 0;
ENUM_TRADE_DIRECTION currentTradeDirection = TRADE_BOTH;
double lastLoggedSpread = 0;
double lastLoggedTotalMovement = 0;
datetime lastDCAEntryTime = 0;  // Last DCA entry time
datetime lastDailyReset = 0;    // Last daily reset time
double dailyProfitTarget = 0;   // Daily profit target in account currency

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit() {
   // Initialize ForexPairs array based on input settings
   string tempPairs[];
   StringSplit(ForexPairsList, ',', tempPairs);
   
   ArrayResize(ForexPairs, ArraySize(tempPairs));
   ArrayCopy(ForexPairs, tempPairs, 0, 0, ArraySize(tempPairs));
   
   // Initialize symbol data
   ArrayResize(symbolData, ArraySize(ForexPairs));
   
   for(int i = 0; i < ArraySize(ForexPairs); i++) {
      symbolData[i].symbol = ForexPairs[i];
      symbolData[i].lastBidPrice = 0;
      symbolData[i].totalPriceMovement = 0;
      symbolData[i].lastPositionTime = TimeCurrent();
      symbolData[i].lastPriceDirectionChange = TimeCurrent();
      symbolData[i].lastPriceDirection = 0;
      symbolData[i].lastSignificantBid = 0;
      symbolData[i].lastOpenTime = 0;
      symbolData[i].lastDCAEntryTime = 0;
      symbolData[i].maxBuyDD = 0;
      symbolData[i].maxSellDD = 0;
      symbolData[i].maxTotalDD = 0;
      symbolData[i].initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      symbolData[i].dailyProfitTarget = symbolData[i].initialBalance * (DailyProfitTarget / 100.0);
      symbolData[i].lastDailyReset = TimeCurrent();
      symbolData[i].currentProfit = 0;
      symbolData[i].totalProfit = 0;
   }
   
   trade.SetExpertMagicNumber(Magic);
   LogMessage("INIT", "EA initialized - Magic: " + IntegerToString(Magic), true);
   LogMessage("INIT", "MinTradeInterval: " + IntegerToString(MinTradeInterval) + " bars", true);
   LogMessage("INIT", "Daily Target: " + DoubleToString(DailyProfitTarget, 2) + "%", true);
   LogMessage("INIT", "Trading pairs: " + IntegerToString(ArraySize(ForexPairs)), true);
   for(int i = 0; i < ArraySize(ForexPairs); i++) {
      LogMessage("INIT", "  - " + ForexPairs[i], true);
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "EA_Info_");
   LogMessage("DEINIT", "EA deinitialized", true);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
   // Traiter chaque paire de devises
   for(int i = 0; i < ArraySize(ForexPairs); i++) {
      ProcessSymbol(ForexPairs[i], symbolData[i]);
   }
}

//+------------------------------------------------------------------+
//| Process a single symbol                                            |
//+------------------------------------------------------------------+
void ProcessSymbol(string symbol, SymbolData &data) {
   // Check daily reset
   MqlDateTime currentTimeStruct;
   TimeToStruct(TimeCurrent(), currentTimeStruct);
   MqlDateTime lastResetTimeStruct;
   TimeToStruct(data.lastDailyReset, lastResetTimeStruct);
   
   // Calculate current profit for this symbol
   data.currentProfit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol) {
            data.currentProfit += PositionGetDouble(POSITION_PROFIT);
         }
      }
   }

   // Calculate closed trades profit
   double closedProfit = 0;
   HistorySelect(data.lastDailyReset, TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic && 
         HistoryDealGetString(ticket, DEAL_SYMBOL) == symbol) {
         closedProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      }
   }

   // Calculate total profit
   data.totalProfit = data.currentProfit + closedProfit;

   // Check if profit target reached for the entire account
   static datetime lastProfitTargetCheck = 0;
   if(TimeCurrent() - lastProfitTargetCheck >= 1) { // Check once per second
      double totalAccountProfit = CalculateTotalAccountProfit();
      if(totalAccountProfit >= ProfitTargetAmount) {
         int totalPositions = 0;
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
               if(PositionGetInteger(POSITION_MAGIC) == Magic) {
                  totalPositions++;
               }
            }
         }
         
         if(totalPositions > 0) {
            double initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            LogMessage("PROFIT", "PROFIT TARGET REACHED! Closing all positions.", true);
            LogMessage("PROFIT", "Final Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + 
                         " USD, Initial Balance: " + DoubleToString(initialBalance, 2) + 
                         " USD, Total Account Profit: " + DoubleToString(totalAccountProfit, 2) + " USD", true);
            
            // Close all positions for all symbols
            for(int i = 0; i < ArraySize(ForexPairs); i++) {
               CloseAllPositions(ForexPairs[i]);
               symbolData[i].currentProfit = 0;
               symbolData[i].totalProfit = 0;
               symbolData[i].initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
               symbolData[i].lastOpenTime = TimeCurrent();
               symbolData[i].lastDailyReset = TimeCurrent();
            }
            
            // Réinitialiser l'historique des trades pour le calcul du profit
            HistorySelect(0, TimeCurrent());
            lastProfitTargetCheck = TimeCurrent();
            return;
         }
      }
      lastProfitTargetCheck = TimeCurrent();
   }
   
   // Check trading hours
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   if(timeStruct.hour < TimeStart || timeStruct.hour >= TimeEnd) {
      return;
   }
   
   // Additional check for real trading mode
   if(!MQLInfoInteger(MQL_TESTER)) {
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) {
         return;
      }
      
      if(SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL) {
         return;
      }
   }
   
   // Single spread check
   double spreadInPips;
   if(!CheckSpread(symbol, spreadInPips)) {
      return;
   }
   
   // Check minimum interval between positions
   if(currentTime - data.lastPositionTime < OpenTime) {
      return;
   }
   
   // Initialize trade conditions
   bool canOpenBuy = false;
   bool canOpenSell = false;
   
   // Check RSI conditions
   double rsi = iRSI(symbol, PERIOD_CURRENT, RsiPeriod, PRICE_CLOSE);
   
   if(RsiMode == RSI_REVERSAL) {
      if(rsi < RsiOversold) {
         canOpenBuy = true;
      }
      if(rsi > RsiOverbought) {
         canOpenSell = true;
      }
   } else {
      if(rsi > RsiOverbought) {
         canOpenBuy = true;
      }
      if(rsi < RsiOversold) {
         canOpenSell = true;
      }
   }
   
   // Check time conditions for new trades
   if(data.lastOpenTime == 0) {
      data.lastOpenTime = currentTime;
      data.lastBidPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
      data.totalPriceMovement = 0;
   }
   
   // Check price movements for new trades
   double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
   
   // Initialize last significant price if needed
   if(data.lastSignificantBid == 0) {
      data.lastSignificantBid = currentBid;
      data.lastBidPrice = currentBid;
      data.lastPriceDirection = 0;
      data.totalPriceMovement = 0;
   }
   
   // Calculate movement from last significant price
   double movementFromLastSignificant = MathAbs(currentBid - data.lastSignificantBid) / (SymbolInfoDouble(symbol, SYMBOL_POINT) * 10);
   
   // If movement is significant, update direction
   if(movementFromLastSignificant >= DirectionChangeThreshold) {
      double newDirection = currentBid > data.lastSignificantBid ? 1 : -1;
      
      if(newDirection != data.lastPriceDirection) {
         data.totalPriceMovement = 0;
         data.lastPriceDirection = newDirection;
         data.lastSignificantBid = currentBid;
         data.lastBidPrice = currentBid;
         data.lastPriceDirectionChange = TimeCurrent();
      }
   }
   
   // Reset total movement if too much time has passed
   if(TimeCurrent() - data.lastPriceDirectionChange > MovementResetTime) {
      data.totalPriceMovement = 0;
      data.lastSignificantBid = currentBid;
      data.lastBidPrice = currentBid;
      data.lastPriceDirectionChange = TimeCurrent();
   }
   
   // Calculate movement from last price
   double priceMovement = MathAbs(currentBid - data.lastBidPrice) / (SymbolInfoDouble(symbol, SYMBOL_POINT) * 10);
   
   if(priceMovement >= MinMovementThreshold) {
      if((data.lastPriceDirection > 0) || (data.lastPriceDirection < 0)) {
         data.totalPriceMovement += priceMovement;
         data.lastBidPrice = currentBid;
      }
   }
   
   // Check conditions based on chosen direction and RSI
   if(TradeDirection == TRADE_BUY_ONLY || TradeDirection == TRADE_BOTH) {
      if(canOpenBuy && data.totalPriceMovement >= PipsStep) {
         OpenBuyOrder(symbol);
         data.totalPriceMovement = 0;
         data.lastOpenTime = TimeCurrent();
         data.lastPositionTime = TimeCurrent();
      }
   }
   
   if(TradeDirection == TRADE_SELL_ONLY || TradeDirection == TRADE_BOTH) {
      if(canOpenSell && data.totalPriceMovement >= PipsStep) {
         OpenSellOrder(symbol);
         data.totalPriceMovement = 0;
         data.lastOpenTime = TimeCurrent();
         data.lastPositionTime = TimeCurrent();
      }
   }
   
   // Update trailing stops and check take profits
   UpdateTrailingStops(symbol);
   
   // Check DCA conditions
   CheckDCAConditions(symbol, data);
}

//+------------------------------------------------------------------+
//| Check Spread Conditions                                           |
//+------------------------------------------------------------------+
bool CheckSpread(string symbol, double &spreadInPips) {
   double currentSpread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   spreadInPips = currentSpread / 10.0;
   
   if(spreadInPips > MaxSpread) {
      LogMessage(symbol, "Spread: " + DoubleToString(spreadInPips, 1) + " > " + DoubleToString(MaxSpread, 1) + " pips - Trading paused");
      return false;
   }
   
   if(spreadInPips > SpreadWarningThreshold) {
      LogMessage(symbol, "WARNING: High spread: " + DoubleToString(spreadInPips, 1) + " pips");
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder(string symbol) {
   if(currentTradeDirection != TRADE_BUY_ONLY && currentTradeDirection != TRADE_BOTH) return;
   
   double spreadInPips;
   if(!CheckSpread(symbol, spreadInPips)) return;
   
   int totalBuyPositions = CountPositions(symbol, POSITION_TYPE_BUY);
   if(totalBuyPositions >= AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2) return;
   
   if(!CheckMinimumDistance(symbol, POSITION_TYPE_BUY)) return;
   
   if(totalBuyPositions < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2) {
      int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_BUY);
      
      if(positionsInCurrentBar == 0) {
         string comment = expertName;
         
         double lotSize = Lots;
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
         double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
         
         lotSize = MathFloor(lotSize / lotStep) * lotStep;
         lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
         
         int maxRetries = 3;
         int retryCount = 0;
         bool orderSuccess = false;
         
         while(!orderSuccess && retryCount < maxRetries) {
            if(MQLInfoInteger(MQL_TESTER)) {
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               request.action = TRADE_ACTION_DEAL;
               request.symbol = symbol;
               request.volume = lotSize;
               request.type = ORDER_TYPE_BUY;
               request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
               request.deviation = 10;
               request.magic = Magic;
               request.comment = comment;
               request.type_filling = ORDER_FILLING_FOK;
               
               if(OrderSend(request, result)) {
                  if(result.retcode == TRADE_RETCODE_DONE) {
                     orderSuccess = true;
                  }
               }
            }
            else {
               if(!trade.Buy(lotSize, symbol, 0, 0, 0, comment)) {
                  int error = GetLastError();
                  if(error == 4756) {
                     double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
                     double spreadInPips = spread / (SymbolInfoDouble(symbol, SYMBOL_POINT) * 10);
                     if(spreadInPips > MaxSpread) {
                        LogMessage(symbol, "E:S(" + DoubleToString(spreadInPips, 1) + ">" + DoubleToString(MaxSpread, 1) + ")");
                        return;
                     }
                  }
                  retryCount++;
                  Sleep(1000);
               } else {
                  orderSuccess = true;
                  LogMessage(symbol, "B:" + DoubleToString(lotSize, 2) + "@" + DoubleToString(SymbolInfoDouble(symbol, SYMBOL_ASK), 5));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                    |
//+------------------------------------------------------------------+
void OpenSellOrder(string symbol) {
   if(currentTradeDirection != TRADE_SELL_ONLY && currentTradeDirection != TRADE_BOTH) return;
   
   double spreadInPips;
   if(!CheckSpread(symbol, spreadInPips)) return;
   
   if(!CheckMinimumDistance(symbol, POSITION_TYPE_SELL)) return;
   
   int totalSellPositions = CountPositions(symbol, POSITION_TYPE_SELL);
   
   if(totalSellPositions < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2) {
      int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_SELL);
      
      if(positionsInCurrentBar == 0) {
         string comment = expertName;
         
         double lotSize = Lots;
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
         double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
         
         lotSize = MathFloor(lotSize / lotStep) * lotStep;
         lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
         
         int maxRetries = 3;
         int retryCount = 0;
         bool orderSuccess = false;
         
         while(!orderSuccess && retryCount < maxRetries) {
            if(MQLInfoInteger(MQL_TESTER)) {
               MqlTradeRequest request = {};
               MqlTradeResult result = {};
               request.action = TRADE_ACTION_DEAL;
               request.symbol = symbol;
               request.volume = lotSize;
               request.type = ORDER_TYPE_SELL;
               request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
               request.deviation = 10;
               request.magic = Magic;
               request.comment = comment;
               request.type_filling = ORDER_FILLING_FOK;
               
               if(OrderSend(request, result)) {
                  if(result.retcode == TRADE_RETCODE_DONE) {
                     orderSuccess = true;
                  }
               }
            }
            else {
               if(!trade.Sell(lotSize, symbol, 0, 0, 0, comment)) {
                  int error = GetLastError();
                  if(error == 4756) {
                     double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
                     double spreadInPips = spread / (SymbolInfoDouble(symbol, SYMBOL_POINT) * 10);
                     if(spreadInPips > MaxSpread) {
                        LogMessage(symbol, "Spread: " + DoubleToString(spreadInPips, 1) + " > " + DoubleToString(MaxSpread, 1));
                        return;
                     }
                  }
                  retryCount++;
                  Sleep(1000);
               } else {
                  orderSuccess = true;
                  LogMessage(symbol, "B:" + DoubleToString(lotSize, 2) + "@" + DoubleToString(SymbolInfoDouble(symbol, SYMBOL_ASK), 5));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count Positions                                                    |
//+------------------------------------------------------------------+
int CountPositions(string symbol, ENUM_POSITION_TYPE positionType) {
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            count++;
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Count Positions in Current Bar                                     |
//+------------------------------------------------------------------+
int CountPositionsInCurrentBar(string symbol, ENUM_POSITION_TYPE positionType) {
   int count = 0;
   datetime currentBarTime = iTime(symbol, PERIOD_CURRENT, 0);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(openTime >= currentBarTime) {
               count++;
            }
         }
      }
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Update Trailing Stops                                              |
//+------------------------------------------------------------------+
void UpdateTrailingStops(string symbol) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol) {
            
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double newSL = 0;
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               double profitInPips = (currentPrice - openPrice) / (SymbolInfoDouble(symbol, SYMBOL_POINT) * 10);
               if(profitInPips >= TralStart) {
                  newSL = currentPrice - Tral * SymbolInfoDouble(symbol, SYMBOL_POINT);
                  if(newSL > currentSL) {
                     trade.PositionModify(PositionGetTicket(i), newSL, PositionGetDouble(POSITION_TP));
                  }
               }
            }
            else {
               double profitInPips = (openPrice - currentPrice) / (SymbolInfoDouble(symbol, SYMBOL_POINT) * 10);
               if(profitInPips >= TralStart) {
                  newSL = currentPrice + Tral * SymbolInfoDouble(symbol, SYMBOL_POINT);
                  if(newSL < currentSL || currentSL == 0) {
                     trade.PositionModify(PositionGetTicket(i), newSL, PositionGetDouble(POSITION_TP));
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check DCA Conditions                                              |
//+------------------------------------------------------------------+
void CheckDCAConditions(string symbol, SymbolData &data) {
    if(TimeCurrent() - data.lastDCAEntryTime < DCAMinDelay) return;
    
    double spreadInPips;
    if(!CheckSpread(symbol, spreadInPips)) return;
    
    double buyTotalProfit = 0;
    double buyAveragePrice = 0;
    double buyTotalLots = 0;
    int buyPositionCount = 0;
    
    double sellTotalProfit = 0;
    double sellAveragePrice = 0;
    double sellTotalLots = 0;
    int sellPositionCount = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
       if(PositionSelectByTicket(PositionGetTicket(i))) {
          if(PositionGetInteger(POSITION_MAGIC) == Magic && 
             PositionGetString(POSITION_SYMBOL) == symbol) {
             
             double positionLots = PositionGetDouble(POSITION_VOLUME);
             double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
             
             if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                buyTotalProfit += PositionGetDouble(POSITION_PROFIT);
                buyAveragePrice += openPrice * positionLots;
                buyTotalLots += positionLots;
                buyPositionCount++;
             }
             else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                sellTotalProfit += PositionGetDouble(POSITION_PROFIT);
                sellAveragePrice += openPrice * positionLots;
                sellTotalLots += positionLots;
                sellPositionCount++;
             }
          }
       }
    }
    
    if(buyTotalLots > 0) buyAveragePrice /= buyTotalLots;
    if(sellTotalLots > 0) sellAveragePrice /= sellTotalLots;
    
    double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
    
    if(TradeDirection != TRADE_SELL_ONLY) {
       if(buyPositionCount > 0) {
          double buyProfitInPoints = (currentBid - buyAveragePrice) / SymbolInfoDouble(symbol, SYMBOL_POINT);
          
          if(buyProfitInPoints >= TakeProfit) {
             LogMessage(symbol, "Close Buy: " + DoubleToString(buyProfitInPoints, 1));
             ClosePositionsInDirection(symbol, POSITION_TYPE_BUY);
          }
          else if(buyProfitInPoints <= -PipsStep) {
             int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_BUY);
             if(positionsInCurrentBar == 0) {
                OpenBuyOrder(symbol);
                data.lastDCAEntryTime = TimeCurrent();
                return;
             }
          }
       }
    }
    
    if(TradeDirection != TRADE_BUY_ONLY) {
       if(sellPositionCount > 0) {
          double sellProfitInPoints = (sellAveragePrice - currentAsk) / SymbolInfoDouble(symbol, SYMBOL_POINT);
          
          if(sellProfitInPoints >= TakeProfit) {
             LogMessage(symbol, "Close Sell: " + DoubleToString(sellProfitInPoints, 1));
             ClosePositionsInDirection(symbol, POSITION_TYPE_SELL);
          }
          else if(sellProfitInPoints <= -PipsStep) {
             int positionsInCurrentBar = CountPositionsInCurrentBar(symbol, POSITION_TYPE_SELL);
             if(positionsInCurrentBar == 0) {
                OpenSellOrder(symbol);
                data.lastDCAEntryTime = TimeCurrent();
                return;
             }
          }
       }
    }
}

//+------------------------------------------------------------------+
//| Check Minimum Distance                                             |
//+------------------------------------------------------------------+
bool CheckMinimumDistance(string symbol, ENUM_POSITION_TYPE positionType) {
   double currentPrice = positionType == POSITION_TYPE_BUY ? 
                        SymbolInfoDouble(symbol, SYMBOL_ASK) : 
                        SymbolInfoDouble(symbol, SYMBOL_BID);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            
            double lastPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double distance = MathAbs(currentPrice - lastPrice) / (SymbolInfoDouble(symbol, SYMBOL_POINT) * 10);
            
            if(distance < MinTradeDistance) {
               return false;
            }
         }
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Close Positions in Direction                                       |
//+------------------------------------------------------------------+
void ClosePositionsInDirection(string symbol, ENUM_POSITION_TYPE positionType, string commentFilter = "") {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            
            if(commentFilter == "" || PositionGetString(POSITION_COMMENT) == commentFilter) {
               double profit = PositionGetDouble(POSITION_PROFIT);
               LogMessage(symbol, "Close " + (positionType == POSITION_TYPE_BUY ? "Buy" : "Sell") + 
                          " positions. Profit: " + DoubleToString(profit, 2) + " USD");
               LogMessage(symbol, "C:" + (profit > 0 ? "+" : "") + DoubleToString(profit, 2));
               trade.PositionClose(PositionGetTicket(i));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close All Positions                                                |
//+------------------------------------------------------------------+
void CloseAllPositions(string symbol) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol) {
            
            double profit = PositionGetDouble(POSITION_PROFIT);
            LogMessage(symbol, "C:" + (profit > 0 ? "+" : "") + DoubleToString(profit, 2));
            trade.PositionClose(PositionGetTicket(i));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update Info Panel                                                  |
//+------------------------------------------------------------------+
void UpdateInfoPanel() {
   if(!Info) return;

   string prefix = "EA_Info_";
   int x = PanelMargin;
   int y = PanelMargin;
   int yStep = FontSize + 10;
   int textMargin = 5;
   int sectionSpacing = 20;
   
   ObjectsDeleteAll(0, prefix);
   
   // Calculate required height based on number of active pairs
   int activePairs = 0;
   for(int i = 0; i < ArraySize(ForexPairs); i++) {
      if(CountPositions(ForexPairs[i], POSITION_TYPE_BUY) > 0 || 
         CountPositions(ForexPairs[i], POSITION_TYPE_SELL) > 0) {
         activePairs++;
      }
   }
   
   int requiredHeight = PanelMargin * 2 + 
                       (4 * yStep) + // EA Status section
                       (activePairs * yStep) + // Forex Pairs section
                       (3 * yStep) + // Total Summary section
                       (2 * yStep); // Daily Target section
   
   int actualHeight = MathMin(requiredHeight, PanelHeight);
   bool needsScroll = requiredHeight > PanelHeight;
   
   // Create background
   string backgroundName = prefix + "Background";
   if(ObjectFind(0, backgroundName) != -1) {
      ObjectDelete(0, backgroundName);
   }
   
   if(!ObjectCreate(0, backgroundName, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
      LogMessage("PANEL", "Error creating background: " + IntegerToString(GetLastError()));
      return;
   }
   
   ObjectSetInteger(0, backgroundName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, backgroundName, OBJPROP_XDISTANCE, x - PanelBorderSize);
   ObjectSetInteger(0, backgroundName, OBJPROP_YDISTANCE, y - PanelBorderSize);
   ObjectSetInteger(0, backgroundName, OBJPROP_XSIZE, PanelWidth);
   ObjectSetInteger(0, backgroundName, OBJPROP_YSIZE, actualHeight);
   ObjectSetInteger(0, backgroundName, OBJPROP_BGCOLOR, C'0,0,0');
   ObjectSetInteger(0, backgroundName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, backgroundName, OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(0, backgroundName, OBJPROP_BACK, false);
   ObjectSetInteger(0, backgroundName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, backgroundName, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, backgroundName, OBJPROP_ZORDER, 0);
   ObjectSetInteger(0, backgroundName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   
   // Section 1: EA Status
   CreateLabel(prefix + "Title", "=== EA Status ===", x + textMargin, y + textMargin, TextColor);
   y += yStep;
   
   // Display current time and trading hours
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   CreateLabel(prefix + "Time", StringFormat("Time: %02d:%02d:%02d (Trading: %02d-%02d)", 
                timeStruct.hour, timeStruct.min, timeStruct.sec, TimeStart, TimeEnd), 
                x + textMargin, y + textMargin, TextColor);
   y += yStep;
   
   // Display RSI mode
   CreateLabel(prefix + "RSIMode", StringFormat("RSI Mode: %s", RsiMode == RSI_REVERSAL ? "Reversal" : "Continuation"), 
                x + textMargin, y + textMargin, TextColor);
   y += yStep;
   
   y += yStep;
   
   // Section 2: Forex Pairs Summary
   CreateLabel(prefix + "PairsTitle", "=== Forex Pairs Summary ===", x + textMargin, y + textMargin, TextColor);
   y += yStep;
   
   // Calculate total positions and profit across all pairs
   int totalPositions = 0;
   double totalProfit = 0;
   double totalLots = 0;
   
   // Sort pairs by profit
   string sortedPairs[];
   double pairProfits[];
   ArrayResize(sortedPairs, ArraySize(ForexPairs));
   ArrayResize(pairProfits, ArraySize(ForexPairs));
   int pairCount = 0;
   
   for(int i = 0; i < ArraySize(ForexPairs); i++) {
      string symbol = ForexPairs[i];
      int buyPositions = CountPositions(symbol, POSITION_TYPE_BUY);
      int sellPositions = CountPositions(symbol, POSITION_TYPE_SELL);
      int pairPositions = buyPositions + sellPositions;
      
      if(pairPositions > 0) {
         double pairProfit = 0;
         double pairLots = 0;
         
         for(int j = PositionsTotal() - 1; j >= 0; j--) {
            if(PositionSelectByTicket(PositionGetTicket(j))) {
               if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                  PositionGetString(POSITION_SYMBOL) == symbol) {
                  pairProfit += PositionGetDouble(POSITION_PROFIT);
                  pairLots += PositionGetDouble(POSITION_VOLUME);
               }
            }
         }
         
         sortedPairs[pairCount] = symbol;
         pairProfits[pairCount] = pairProfit;
         pairCount++;
         
         totalPositions += pairPositions;
         totalProfit += pairProfit;
         totalLots += pairLots;
      }
   }
   
   // Sort pairs by profit (highest first)
   for(int i = 0; i < pairCount - 1; i++) {
      for(int j = i + 1; j < pairCount; j++) {
         if(pairProfits[j] > pairProfits[i]) {
            string tempPair = sortedPairs[i];
            double tempProfit = pairProfits[i];
            sortedPairs[i] = sortedPairs[j];
            pairProfits[i] = pairProfits[j];
            sortedPairs[j] = tempPair;
            pairProfits[j] = tempProfit;
         }
      }
   }
   
   // Display pairs (limited by MaxVisiblePairs)
   int displayCount = MathMin(pairCount, MaxVisiblePairs);
   for(int i = 0; i < displayCount; i++) {
      string symbol = sortedPairs[i];
      double pairProfit = pairProfits[i];
      int buyPositions = CountPositions(symbol, POSITION_TYPE_BUY);
      int sellPositions = CountPositions(symbol, POSITION_TYPE_SELL);
      int pairPositions = buyPositions + sellPositions;
      double pairLots = 0;
      
      for(int j = PositionsTotal() - 1; j >= 0; j--) {
         if(PositionSelectByTicket(PositionGetTicket(j))) {
            if(PositionGetInteger(POSITION_MAGIC) == Magic && 
               PositionGetString(POSITION_SYMBOL) == symbol) {
               pairLots += PositionGetDouble(POSITION_VOLUME);
            }
         }
      }
      
      color pairColor = pairProfit >= 0 ? clrLime : clrRed;
      CreateLabel(prefix + "Pair_" + symbol, 
                 StringFormat("%s: %d pos (%.2f lots) %s%.2f", 
                 symbol, pairPositions, pairLots, 
                 pairProfit >= 0 ? "+" : "", pairProfit),
                 x + textMargin, y + textMargin, pairColor);
      y += yStep;
   }
   
   // Show "More..." if there are additional pairs
   if(pairCount > MaxVisiblePairs) {
      CreateLabel(prefix + "MorePairs", 
                 StringFormat("... and %d more pairs", pairCount - MaxVisiblePairs),
                 x + textMargin, y + textMargin, TextColor);
      y += yStep;
   }
   
   y += yStep;
   
   // Section 3: Total Summary
   CreateLabel(prefix + "TotalTitle", "=== Total Summary ===", x + textMargin, y + textMargin, TextColor);
   y += yStep;
   
   CreateLabel(prefix + "TotalPositions", StringFormat("Total Positions: %d (%.2f lots)", totalPositions, totalLots), 
                x + textMargin, y + textMargin, TextColor);
   y += yStep;
   
   color totalColor = totalProfit >= 0 ? clrLime : clrRed;
   CreateLabel(prefix + "TotalProfit", StringFormat("Total Profit: %s%.2f", totalProfit >= 0 ? "+" : "", totalProfit), 
                x + textMargin, y + textMargin, totalColor);
   y += yStep;
   
   // Daily Target Progress
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyProfit = currentEquity - initialBalance;
   double progressToTarget = (dailyProfit / (initialBalance * (DailyProfitTarget / 100.0))) * 100;
   color progressColor = dailyProfit >= 0 ? clrLime : clrRed;
   
   CreateLabel(prefix + "DailyTarget", 
               StringFormat("Daily Target: %.1f%% (Progress: %.1f%%)", 
               DailyProfitTarget, progressToTarget),
               x + textMargin, y + textMargin, progressColor);
   y += yStep;
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Create Label for Info Panel                                        |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr) {
   if(ObjectFind(0, name) != -1) {
      ObjectDelete(0, name);
   }
   
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
      LogMessage("PANEL", "Error creating label: " + IntegerToString(GetLastError()));
      return;
   }
   
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Universal Logging Function                                         |
//+------------------------------------------------------------------+
void LogMessage(string symbol, string message, bool forceLog = false) {
   datetime currentTime = TimeCurrent();
   string timeStr = TimeToString(currentTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   
   // Ne logger que si le message concerne le ProfitTargetAmount
   if(StringFind(message, "PROFIT TARGET REACHED") >= 0) {
      double totalAccountProfit = CalculateTotalAccountProfit();
      Print(timeStr + "   PROFIT TARGET REACHED! Total Profit: " + DoubleToString(totalAccountProfit, 2) + " USD");
   }
}

//+------------------------------------------------------------------+
//| Calculate total account profit                                     |
//+------------------------------------------------------------------+
double CalculateTotalAccountProfit() {
   double totalProfit = 0;
   
   // Calculate profit from open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic) {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
         }
      }
   }
   
   // Calculate profit from closed trades since last global reset
   datetime lastGlobalReset = 0;
   for(int i = 0; i < ArraySize(ForexPairs); i++) {
      if(symbolData[i].lastDailyReset > lastGlobalReset) {
         lastGlobalReset = symbolData[i].lastDailyReset;
      }
   }
   
   // Select history since last global reset
   HistorySelect(lastGlobalReset, TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic) {
         totalProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      }
   }
   
   return totalProfit;
} 