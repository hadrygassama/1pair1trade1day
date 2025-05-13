//+------------------------------------------------------------------+
//|                                              ReversalCanBeProfitable.mq5 |
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

// Trend Direction
enum ENUM_TREND_DIRECTION {
   TREND_UP,          // Uptrend
   TREND_DOWN,        // Downtrend
   TREND_SIDEWAYS    // Sideways
};

// Forex pairs to trade
string ForexPairs[];

// Variables globales pour la gestion des logs
static datetime lastIntervalLogTime = 0;
static datetime lastSpreadLogTime = 0;
static datetime lastDirectionLogTime = 0;
static datetime lastTradeLogTime = 0;
static datetime lastDCALogTime = 0;
static const int MIN_LOG_INTERVAL = 30; // Augmenté à 30 secondes entre les logs similaires
static double lastLoggedPrice = 0;      // Pour suivre le dernier prix logué
static const double PRICE_CHANGE_THRESHOLD = 0.5; // Minimum 0.5 pips de changement pour reloger

// Structure pour stocker les données par paire
struct SymbolData {
   string symbol;
   datetime lastOpenTime;
   double initialBalance;
   datetime lastDailyReset;
   double currentProfit;  // Profit des trades ouverts
   double totalProfit;    // Profit total (trades ouverts + fermés)
   int maFastHandle;      // Handle pour la MA rapide
   int maSlowHandle;      // Handle pour la MA lente
   double lastFastMA;     // Dernière valeur MA rapide
   double lastSlowMA;     // Dernière valeur MA lente
   datetime lastBarTime;  // Temps de la dernière barre vérifiée
};

// Tableau pour stocker les données de chaque paire
SymbolData symbolData[];

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Trading Direction Settings ==="
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Direction
input int      Magic = 123456;              // Magic number for trade identification
input string   ExpertName = "MAPullback";       // Expert Advisor name for trade comments

input group "=== Position Management Settings ==="
input double   Lots = 0.25;                 // Trading volume in lots
input int      TimeStart = 0;               // Trading start hour (0-23)
input int      TimeEnd = 23;                // Trading end hour (0-23)
input double   MaxSpread = 40;              // Maximum allowed spread in pips

input group "=== Trend Settings ==="
input int      FastMAPeriod = 8;            // Fast MA Period
input int      SlowMAPeriod = 12;           // Slow MA Period
input ENUM_MA_METHOD MAMethod = MODE_EMA;   // MA Method
input ENUM_APPLIED_PRICE MAPrice = PRICE_CLOSE; // MA Applied Price

input group "=== Exit Settings ==="
input double   TakeProfit = 0.0;           // Take Profit in pips
input double   TrailingStop = 0.0;         // Trailing Stop in pips
input double   TrailingStep = 0.0;          // Trailing Step in pips
input double   ProfitTargetAmount = 0.0;    // Profit target amount in USD to close all positions (0 = disabled)
input bool     ExitOnOppositeSignal = true; // Exit when opposite signal appears
input double   PartialClosePercent = 30;    // Partial Close Percentage (0 = disabled)
input double   MinProfitForPartialClose = 100; // Minimum Profit for Partial Close (points, 0 = disabled)
input int      RSIPeriod = 14;             // RSI Period
input double   RSIOverbought = 70;         // RSI Overbought Level
input double   RSIOversold = 30;           // RSI Oversold Level

input group "=== Forex Pairs Settings ==="
input string   ForexPairsList = "EURUSD,GBPUSD,USDJPY,EURJPY,GBPJPY,AUDUSD,EURGBP,USDCHF,EURCHF,GBPCHF";  // Top 10 pairs for trend-based scalping

// Global variables
CTrade trade;
string expertName = ExpertName;
datetime lastOpenTime = 0;
ENUM_TRADE_DIRECTION currentTradeDirection = TRADE_BOTH;
datetime lastDailyReset = 0;    // Last daily reset time

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit() {
   // Initialize ForexPairs array based on input settings
   string pairs[];
   StringSplit(ForexPairsList, ',', pairs);
   ArrayResize(ForexPairs, ArraySize(pairs));
   ArrayCopy(ForexPairs, pairs);
   
   // Initialize symbol data
   ArrayResize(symbolData, ArraySize(ForexPairs));
   
   for(int i = 0; i < ArraySize(ForexPairs); i++) {
      symbolData[i].symbol = ForexPairs[i];
      symbolData[i].lastOpenTime = 0;
      symbolData[i].initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      symbolData[i].lastDailyReset = TimeCurrent();
      symbolData[i].currentProfit = 0;
      symbolData[i].totalProfit = 0;
      symbolData[i].lastBarTime = 0;
      
      // Initialize indicators
      symbolData[i].maFastHandle = iMA(ForexPairs[i], PERIOD_CURRENT, FastMAPeriod, 0, MAMethod, MAPrice);
      symbolData[i].maSlowHandle = iMA(ForexPairs[i], PERIOD_CURRENT, SlowMAPeriod, 0, MAMethod, MAPrice);
      
      if(symbolData[i].maFastHandle == INVALID_HANDLE || 
         symbolData[i].maSlowHandle == INVALID_HANDLE) {
         Print("Error creating indicators for ", ForexPairs[i]);
         return INIT_FAILED;
      }
   }
   
   trade.SetExpertMagicNumber(Magic);
   Print("EA initialized - Magic: ", Magic);
   Print("Trading pairs: ", ArraySize(ForexPairs));
   for(int i = 0; i < ArraySize(ForexPairs); i++) {
      Print("  - ", ForexPairs[i]);
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Release indicator handles
   for(int i = 0; i < ArraySize(ForexPairs); i++) {
      IndicatorRelease(symbolData[i].maFastHandle);
      IndicatorRelease(symbolData[i].maSlowHandle);
   }
   Print("EA deinitialized");
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
   
   // Trading signals
   bool canOpenBuy = false;
   bool canOpenSell = false;
   
   // Get current bar time
   datetime currentBarTime = iTime(symbol, PERIOD_CURRENT, 0);
   
   // Update last bar time
   data.lastBarTime = currentBarTime;
   
   // Check trading hours
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   
   if(timeStruct.hour < TimeStart || timeStruct.hour >= TimeEnd) {
      Print(symbol, " - Outside trading hours: Current hour=", timeStruct.hour, " (", TimeStart, "-", TimeEnd, ")");
      return;
   }
   
   // Get indicator values
   double fastMABuffer[], slowMABuffer[];
   ArraySetAsSeries(fastMABuffer, true);
   ArraySetAsSeries(slowMABuffer, true);
   
   if(CopyBuffer(data.maFastHandle, 0, 0, 3, fastMABuffer) <= 0 ||
      CopyBuffer(data.maSlowHandle, 0, 0, 3, slowMABuffer) <= 0) {
      Print(symbol, " - Error copying indicator buffers");
      return;
   }
   
   // Update last values
   data.lastFastMA = fastMABuffer[0];
   data.lastSlowMA = slowMABuffer[0];
   
   // Get current price data
   double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double currentSpread = currentAsk - currentBid;
   double spreadInPips = currentSpread / (SymbolInfoDouble(symbol, SYMBOL_POINT) * 10);
   
   // Log EMA values for every bar
   Print(symbol, " - Bar Time: ", TimeToString(currentBarTime), 
         " - EMA Values - Fast[0]=", fastMABuffer[0], " Slow[0]=", slowMABuffer[0], 
         " Fast[1]=", fastMABuffer[1], " Slow[1]=", slowMABuffer[1],
         " Spread=", spreadInPips, " pips");
   
   // Check for MA crossovers with confirmation
   bool crossedUp = fastMABuffer[1] < slowMABuffer[1] && fastMABuffer[0] > slowMABuffer[0];
   bool crossedDown = fastMABuffer[1] > slowMABuffer[1] && fastMABuffer[0] < slowMABuffer[0];
   
   // Log detailed crossover analysis
   Print(symbol, " - CROSSOVER ANALYSIS:");
   Print(symbol, " - Previous bar: Fast=", fastMABuffer[1], " Slow=", slowMABuffer[1], 
         " Diff=", fastMABuffer[1] - slowMABuffer[1]);
   Print(symbol, " - Current bar: Fast=", fastMABuffer[0], " Slow=", slowMABuffer[0], 
         " Diff=", fastMABuffer[0] - slowMABuffer[0]);
   
   // Log market conditions for debugging
   if(crossedUp || crossedDown) {
      Print(symbol, " - Market Conditions - Ask=", currentAsk, " Bid=", currentBid, 
            " Spread=", spreadInPips, " pips");
      Print(symbol, " - EMA Values - Fast[0]=", fastMABuffer[0], " Slow[0]=", slowMABuffer[0], 
            " Fast[1]=", fastMABuffer[1], " Slow[1]=", slowMABuffer[1]);
      
      // Log current positions
      int totalPositions = PositionsTotal();
      Print(symbol, " - Current Positions: ", totalPositions);
      for(int i = 0; i < totalPositions; i++) {
         if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetInteger(POSITION_MAGIC) == Magic && 
               PositionGetString(POSITION_SYMBOL) == symbol) {
               Print(symbol, " - Position #", i, " Type=", 
                     PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "Buy" : "Sell",
                     " Open Price=", PositionGetDouble(POSITION_PRICE_OPEN));
            }
         }
      }
   }
   
   // Set trading signals based on crossovers
   if(crossedUp) {
      Print(symbol, " - CROSSOVER UP DETECTED - Previous: Fast=", fastMABuffer[1], " Slow=", slowMABuffer[1], 
            " Current: Fast=", fastMABuffer[0], " Slow=", slowMABuffer[0]);
      canOpenBuy = true;
      // Vérifier s'il n'y a pas déjà une position d'achat ouverte
      if(CountPositions(symbol, POSITION_TYPE_BUY) == 0) {
         OpenBuyOrder(symbol, data);
      }
   }
   else if(crossedDown) {
      Print(symbol, " - CROSSOVER DOWN DETECTED - Previous: Fast=", fastMABuffer[1], " Slow=", slowMABuffer[1], 
            " Current: Fast=", fastMABuffer[0], " Slow=", slowMABuffer[0]);
      canOpenSell = true;
      // Vérifier s'il n'y a pas déjà une position de vente ouverte
      if(CountPositions(symbol, POSITION_TYPE_SELL) == 0) {
         OpenSellOrder(symbol, data);
      }
   }
   else {
      Print(symbol, " - NO CROSSOVER - Fast EMA is ", 
            fastMABuffer[0] > slowMABuffer[0] ? "above" : "below", 
            " Slow EMA");
   }
   
   // Update positions and check take profits
   UpdatePositions(symbol, canOpenBuy, canOpenSell);
}

//+------------------------------------------------------------------+
//| Check Spread Conditions                                           |
//+------------------------------------------------------------------+
bool CheckSpread(string symbol, double &spreadInPips) {
   double currentSpread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
   spreadInPips = currentSpread / (SymbolInfoDouble(symbol, SYMBOL_POINT) * 10);
   
   if(spreadInPips > MaxSpread) {
      if(TimeCurrent() - lastSpreadLogTime >= MIN_LOG_INTERVAL) {
         Print(symbol, " - Spread: ", spreadInPips, " > ", MaxSpread, " pips - Trading paused");
         lastSpreadLogTime = TimeCurrent();
      }
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder(string symbol, SymbolData &data) {
   if(currentTradeDirection != TRADE_BUY_ONLY && currentTradeDirection != TRADE_BOTH) return;
   
   double spreadInPips;
   if(!CheckSpread(symbol, spreadInPips)) return;
   
   int totalBuyPositions = CountPositions(symbol, POSITION_TYPE_BUY);
   if(totalBuyPositions >= AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2) return;
   
   string comment = expertName;
   
   double lotSize = Lots;
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double pipValue = point * 10;
   double tp = (TakeProfit > 0) ? ask + (TakeProfit * pipValue) : 0;
   
   int maxRetries = 3;
   int retryCount = 0;
   bool orderSuccess = false;
   
   while(!orderSuccess && retryCount < maxRetries) {
      if(!trade.Buy(lotSize, symbol, ask, 0, tp, comment)) {  // SL set to 0
         int error = GetLastError();
         if(error == 4756) {
            double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
            double spreadInPips = spread / pipValue;
            if(spreadInPips > MaxSpread) {
               Print(symbol, " - E:S(", spreadInPips, ">", MaxSpread, ")");
               return;
            }
         }
         retryCount++;
         Sleep(1000);
      } else {
         orderSuccess = true;
         Print(symbol, " - Buy order opened: Lot=", lotSize, " Price=", ask, " TP=", tp);
         data.lastOpenTime = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                    |
//+------------------------------------------------------------------+
void OpenSellOrder(string symbol, SymbolData &data) {
   if(currentTradeDirection != TRADE_SELL_ONLY && currentTradeDirection != TRADE_BOTH) return;
   
   double spreadInPips;
   if(!CheckSpread(symbol, spreadInPips)) return;
   
   int totalSellPositions = CountPositions(symbol, POSITION_TYPE_SELL);
   if(totalSellPositions >= AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2) return;
   
   string comment = expertName;
   
   double lotSize = Lots;
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double pipValue = point * 10;
   double tp = (TakeProfit > 0) ? bid - (TakeProfit * pipValue) : 0;
   
   int maxRetries = 3;
   int retryCount = 0;
   bool orderSuccess = false;
   
   while(!orderSuccess && retryCount < maxRetries) {
      if(!trade.Sell(lotSize, symbol, bid, 0, tp, comment)) {  // SL set to 0
         int error = GetLastError();
         if(error == 4756) {
            double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
            double spreadInPips = spread / pipValue;
            if(spreadInPips > MaxSpread) {
               Print(symbol, " - Spread: ", spreadInPips, " > ", MaxSpread);
               return;
            }
         }
         retryCount++;
         Sleep(1000);
      } else {
         orderSuccess = true;
         Print(symbol, " - Sell order opened: Lot=", lotSize, " Price=", bid, " TP=", tp);
         data.lastOpenTime = TimeCurrent();
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
//| Update Positions                                                   |
//+------------------------------------------------------------------+
void UpdatePositions(string symbol, bool canOpenBuy, bool canOpenSell) {
   static bool wasAboveUpperLevel = false;  // Pour suivre si le RSI était déjà au-dessus de 70
   static bool wasBelowLowerLevel = false;  // Pour suivre si le RSI était déjà en dessous de 30
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol) {
            
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            double pipValue = point * 10;
            bool isBuyPosition = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
            
            // Check for opposite signal if enabled
            if(ExitOnOppositeSignal) {
               bool oppositeSignal = (isBuyPosition && canOpenSell) || (!isBuyPosition && canOpenBuy);
               
               if(oppositeSignal) {
                  trade.PositionClose(PositionGetTicket(i));
                  Print(symbol, " - Close position due to opposite signal");
                  continue;
               }
            }
            
            // Check for partial close conditions
            if(PartialClosePercent > 0 && MinProfitForPartialClose > 0) {
               double profitInPoints = isBuyPosition ? 
                  (currentPrice - openPrice) / point : 
                  (openPrice - currentPrice) / point;
               
               if(profitInPoints >= MinProfitForPartialClose) {
                  // Get RSI value
                  double rsiBuffer[];
                  ArraySetAsSeries(rsiBuffer, true);
                  int rsiHandle = iRSI(symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE);
                  
                  if(CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer) > 0) {
                     double currentRSI = rsiBuffer[0];
                     bool shouldClose = false;
                     
                     if(isBuyPosition) {
                        // Vérifie si le RSI vient de passer au-dessus de 70
                        if(currentRSI > RSIOverbought && !wasAboveUpperLevel) {
                           shouldClose = true;
                           wasAboveUpperLevel = true;
                           Print("RSI crossed UP level for BUY position - Current: ", DoubleToString(currentRSI, 2));
                        }
                        // Réinitialise le flag quand le RSI redescend en dessous de 70
                        else if(currentRSI <= RSIOverbought) {
                           wasAboveUpperLevel = false;
                        }
                     }
                     else {
                        // Vérifie si le RSI vient de passer en dessous de 30
                        if(currentRSI < RSIOversold && !wasBelowLowerLevel) {
                           shouldClose = true;
                           wasBelowLowerLevel = true;
                           Print("RSI crossed DOWN level for SELL position - Current: ", DoubleToString(currentRSI, 2));
                        }
                        // Réinitialise le flag quand le RSI remonte au-dessus de 30
                        else if(currentRSI >= RSIOversold) {
                           wasBelowLowerLevel = false;
                        }
                     }
                     
                     if(shouldClose) {
                        double volume = PositionGetDouble(POSITION_VOLUME);
                        double partialVolume = volume * (PartialClosePercent / 100.0);
                        
                        // Get minimum lot size and lot step
                        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
                        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
                        
                        // Round partial volume to valid lot size
                        partialVolume = MathFloor(partialVolume / lotStep) * lotStep;
                        partialVolume = MathMax(minLot, partialVolume);
                        
                        // Ensure we don't try to close more than the position volume
                        partialVolume = MathMin(partialVolume, volume);
                        
                        if(trade.PositionClosePartial(PositionGetTicket(i), partialVolume)) {
                           Print(symbol, " - Partial close ", PartialClosePercent, "% of ", 
                                 (isBuyPosition ? "BUY" : "SELL"), " position at RSI=", currentRSI, 
                                 " (Volume=", partialVolume, " of ", volume, ")");
                        } else {
                           Print(symbol, " - Failed to partially close position. Error: ", GetLastError());
                        }
                     }
                  }
                  IndicatorRelease(rsiHandle);
               }
            }
            
            // Only check Take Profit and Trailing Stop if they are enabled
            if(TakeProfit > 0 || TrailingStop > 0) {
               if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                  double profitInPips = (currentPrice - openPrice) / pipValue;
                  
                  // Check Take Profit
                  if(TakeProfit > 0 && profitInPips >= TakeProfit) {
                     trade.PositionClose(PositionGetTicket(i));
                     Print(symbol, " - Close Buy: Take Profit reached at ", profitInPips, " pips");
                     continue;
                  }
                  
                  // Update Trailing Stop only if enabled and profit exceeds TrailingStop
                  if(TrailingStop > 0 && profitInPips >= TrailingStop) {
                     double newSL = currentPrice - (TrailingStop * pipValue);
                     if(currentSL == 0 || newSL > currentSL + (TrailingStep * pipValue)) {
                        trade.PositionModify(PositionGetTicket(i), newSL, 0);
                        Print(symbol, " - Update Buy Trailing Stop: ", newSL, " (Profit: ", profitInPips, " pips)");
                     }
                  }
               }
               else {
                  double profitInPips = (openPrice - currentPrice) / pipValue;
                  
                  // Check Take Profit
                  if(TakeProfit > 0 && profitInPips >= TakeProfit) {
                     trade.PositionClose(PositionGetTicket(i));
                     Print(symbol, " - Close Sell: Take Profit reached at ", profitInPips, " pips");
                     continue;
                  }
                  
                  // Update Trailing Stop only if enabled and profit exceeds TrailingStop
                  if(TrailingStop > 0 && profitInPips >= TrailingStop) {
                     double newSL = currentPrice + (TrailingStop * pipValue);
                     if(currentSL == 0 || newSL < currentSL - (TrailingStep * pipValue)) {
                        trade.PositionModify(PositionGetTicket(i), newSL, 0);
                        Print(symbol, " - Update Sell Trailing Stop: ", newSL, " (Profit: ", profitInPips, " pips)");
                     }
                  }
               }
            }
         }
      }
   }
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
               Print(symbol, " - Close ", positionType == POSITION_TYPE_BUY ? "Buy" : "Sell", 
                     ": ", profit > 0 ? "+" : "", profit);
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
            Print(symbol, " - C:", profit > 0 ? "+" : "", profit);
            trade.PositionClose(PositionGetTicket(i));
         }
      }
   }
} 