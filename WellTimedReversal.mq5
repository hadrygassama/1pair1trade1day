//+------------------------------------------------------------------+
//|                                                      WellTimedReversal.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Indicators\Indicators.mqh>

// Enumération pour la direction de trading
enum ENUM_TRADE_DIRECTION {
   TRADE_BUY = 0,    // Trading Buy only
   TRADE_SELL = 1,   // Trading Sell only
   TRADE_BOTH = 2    // Trading both directions
};

// Structure pour stocker les informations par paire
struct SymbolData {
   string symbol;
   CTrade trade;
   double lastBidPrice;
   datetime lastOpenTime;
   datetime lastBuyPositionTime;
   datetime lastSellPositionTime;
   double maxBuyDD;
   double maxSellDD;
   double maxTotalDD;
   double totalPriceMovement;
   double cachedBuyProfit;
   double cachedSellProfit;
   double cachedBuyLots;
   double cachedSellLots;
   int cachedBuyPositions;
   int cachedSellPositions;
   datetime lastCacheUpdate;
   bool cacheNeedsUpdate;
   double lastRSI;
   bool rsiCrossedUp;
   bool rsiCrossedDown;
   int dailyTradesCount;      // Nombre de trades du jour
   datetime lastTradeDate;    // Date du dernier trade
   int emaHandle;                      // Handle pour l'indicateur EMA
   int emaFastHandle;                  // Handle pour l'indicateur EMA rapide
   double lastEMA;                     // Dernière valeur EMA lente
   double lastFastEMA;                 // Dernière valeur EMA rapide
};

// Expert parameters
input group "=== Configuration Générale ==="
input string   TradingPairs = "EURUSD,GBPUSD,USDJPY";  // Pairs to trade
input int      Magic = 123456;         // EA ID
input bool     ShowTradeLogs = true;  // Show logs

input group "=== Paramètres de Trading ==="
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Direction
input int      PipsStep = 1;          // Price step
input int      MaxSpread = 50;         // Max spread
input bool     UseMinDistance = false;  // Min distance
input int      MinDistancePips = 30;   // Min distance pips
input bool     UseMinTime = false;      // Min time
input int      OpenTime = 60;          // Min time sec
input int      MaxDailyTrades = 10;    // Max trades/day

input group "=== Paramètres RSI ==="
input int      RSIPeriod = 14;         // Period
input int      RSIOverbought = 70;     // Overbought
input int      RSIOversold = 30;       // Oversold
input bool     UseRSIReversal = false; // Use RSI reversal logic (false = continuation)

input group "=== Paramètres EMA ==="
input bool     UseEMAFilter = true;   // Enable filter
input int      EMAPeriod = 200;        // EMA lente
input int      EMAFastPeriod = 50;     // EMA rapide
input bool     BuyAboveEMA = true;     // Buy above EMA
input bool     SellAboveEMA = false;    // Sell above EMA

input group "=== Gestion des Positions ==="
input double   Lots = 0.1;             // Base lot
input double   LotMultiplier = 1.5;    // Multiplier
input double   MaxLot = 1.5;           // Max lot
input bool     EnableMaxPosition = false;     // Enable limits
input int      MaxBuyPositions = 30;    // Max Buy
input int      MaxSellPositions = 30;   // Max Sell

input group "=== Heures de Trading ==="
input int      TimeStartHour = 0;      // Start hour
input int      TimeStartMinute = 0;    // Start minute
input int      TimeEndHour = 23;       // End hour
input int      TimeEndMinute = 59;     // End minute

input group "=== Gestion des Sorties ==="
input int      Tral = 30;             // Trailing stop
input int      TralStart = 50;        // Start trailing
input double   TakeProfit = 100;       // Take profit
input double   StopLoss = 500;         // Stop loss
input bool     UseWeightedExit = true; // Weighted exit
input bool     GroupByDirection = true; // Group by direction

input group "=== Paramètres d'Interface ==="
input bool     Info = true;            // Show panel
input int      FontSize = 12;          // Font size
input color    TextColor = clrWhite;   // Text color

// Global variables
string expertName = "WellTimedReversal";
double initialBalance = 0;
datetime lastLogTime = 0;
double lastSpread = 0;
double lastLoggedMovement = 0;
int cacheUpdateInterval = 5;

// Tableau pour stocker les données de chaque paire
SymbolData symbols[];

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit() {
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Initialiser les paires de trading
   string pairs[];
   StringSplit(TradingPairs, ',', pairs);
   ArrayResize(symbols, ArraySize(pairs));
   
   for(int i = 0; i < ArraySize(pairs); i++) {
      symbols[i].symbol = pairs[i];
      symbols[i].trade.SetExpertMagicNumber(Magic);
      symbols[i].lastBidPrice = 0;
      symbols[i].lastOpenTime = 0;
      symbols[i].lastBuyPositionTime = 0;
      symbols[i].lastSellPositionTime = 0;
      symbols[i].maxBuyDD = 0;
      symbols[i].maxSellDD = 0;
      symbols[i].maxTotalDD = 0;
      symbols[i].totalPriceMovement = 0;
      symbols[i].cachedBuyProfit = 0;
      symbols[i].cachedSellProfit = 0;
      symbols[i].cachedBuyLots = 0;
      symbols[i].cachedSellLots = 0;
      symbols[i].cachedBuyPositions = 0;
      symbols[i].cachedSellPositions = 0;
      symbols[i].lastCacheUpdate = 0;
      symbols[i].cacheNeedsUpdate = true;
      symbols[i].lastRSI = 0;
      symbols[i].rsiCrossedUp = false;
      symbols[i].rsiCrossedDown = false;
      symbols[i].dailyTradesCount = 0;
      symbols[i].lastTradeDate = 0;
      
      // Initialiser les indicateurs EMA si le filtre est activé
      if(UseEMAFilter) {
         symbols[i].emaHandle = iMA(symbols[i].symbol, PERIOD_CURRENT, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
         symbols[i].emaFastHandle = iMA(symbols[i].symbol, PERIOD_CURRENT, EMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
         
         if(symbols[i].emaHandle == INVALID_HANDLE || symbols[i].emaFastHandle == INVALID_HANDLE) {
            PrintFormat("Error creating EMA indicators for %s", symbols[i].symbol);
            return INIT_FAILED;
         }
      }
   }
   
   PrintFormat("EA initialized - Magic: %d", Magic);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Libérer les handles des indicateurs
   for(int i = 0; i < ArraySize(symbols); i++) {
      if(UseEMAFilter) {
         if(symbols[i].emaHandle != INVALID_HANDLE) IndicatorRelease(symbols[i].emaHandle);
         if(symbols[i].emaFastHandle != INVALID_HANDLE) IndicatorRelease(symbols[i].emaFastHandle);
      }
   }
   
   ObjectsDeleteAll(0, "EA_Info_");
   PrintFormat("EA deinitialized - Reason: %d", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
   // Update panel first
   if(Info) UpdateInfoPanel();
   
   // Vérification de la connexion au serveur
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) {
      PrintStatusLine();
      return;
   }
   
   // Check trading hours using server GMT time
   datetime currentTime = TimeCurrent();  // Server local time
   datetime gmtTime = TimeGMT();         // Server GMT time (trading server time)
   
   MqlDateTime timeStruct;
   TimeToStruct(gmtTime, timeStruct);
   
   int gmtHour = timeStruct.hour;
   int gmtMinute = timeStruct.min;
   
   // Convert trading hours to minutes for comparison
   int currentTimeInMinutes = gmtHour * 60 + gmtMinute;
   int startTimeInMinutes = TimeStartHour * 60 + TimeStartMinute;
   int endTimeInMinutes = TimeEndHour * 60 + TimeEndMinute;
   
   if(currentTimeInMinutes < startTimeInMinutes || currentTimeInMinutes >= endTimeInMinutes) {
      PrintStatusLine();
      return;
   }
   
   // Traiter chaque paire
   for(int i = 0; i < ArraySize(symbols); i++) {
      ProcessSymbol(symbols[i], currentTime);
   }
   
   // Print status line every second
   if(currentTime - lastLogTime >= 1) {
      PrintStatusLine();
      lastLogTime = currentTime;
   }
}

//+------------------------------------------------------------------+
//| Process a single symbol                                            |
//+------------------------------------------------------------------+
void ProcessSymbol(SymbolData &symbol, datetime currentTime) {
   // Vérifier et réinitialiser le compteur de trades quotidiens si nécessaire
   MqlDateTime currentDate;
   TimeToStruct(currentTime, currentDate);
   currentDate.hour = 0;
   currentDate.min = 0;
   currentDate.sec = 0;
   datetime today = StructToTime(currentDate);
   
   if(symbol.lastTradeDate < today) {
      symbol.dailyTradesCount = 0;
      symbol.lastTradeDate = today;
   }
   
   // Get current price
   double currentBid = SymbolInfoDouble(symbol.symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(symbol.symbol, SYMBOL_ASK);
   
   // Check spread
   double currentSpread = SymbolInfoDouble(symbol.symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol.symbol, SYMBOL_BID);
   
   // Get the number of digits for the symbol
   int digits = (int)SymbolInfoInteger(symbol.symbol, SYMBOL_DIGITS);
   
   // Calculate spread in pips based on the number of digits
   double spreadInPips;
   if(digits == 2 || digits == 3) {
      spreadInPips = currentSpread * 10;
   } else if(digits == 4 || digits == 5) {
      spreadInPips = currentSpread * 10000;
   } else {
      spreadInPips = currentSpread / _Point;
   }
   
   if(spreadInPips > MaxSpread) {
      return;
   }
   
   // Update position cache for this symbol
   UpdatePositionCache(symbol);
   
   // Get RSI values
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   int rsiHandle = iRSI(symbol.symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE);
   CopyBuffer(rsiHandle, 0, 0, 2, rsiBuffer);
   
   if(ArraySize(rsiBuffer) < 2) return;
   
   double currentRSI = rsiBuffer[0];
   double previousRSI = rsiBuffer[1];
   
   // Log des valeurs RSI
   if(ShowTradeLogs) {
      PrintFormat("[%s] RSI Values - Current: %.2f, Previous: %.2f, Overbought: %d, Oversold: %d", 
                 symbol.symbol, currentRSI, previousRSI, RSIOverbought, RSIOversold);
   }
   
   // Check for RSI crosses
   bool rsiCrossedUp = false;
   bool rsiCrossedDown = false;
   
   if(UseRSIReversal) {
      // Logique de renversement (Reversal)
      // Signal d'achat quand le RSI passe de en-dessous 30 à au-dessus de 30
      if(previousRSI <= RSIOversold && currentRSI > RSIOversold) {
         symbol.rsiCrossedUp = true;
         rsiCrossedUp = true;
         if(ShowTradeLogs) {
            PrintFormat("[%s] RSI Reversal - Buy Signal: Previous: %.2f <= %d, Current: %.2f > %d", 
                       symbol.symbol, previousRSI, RSIOversold, currentRSI, RSIOversold);
         }
      }
      
      // Signal de vente quand le RSI passe de au-dessus 70 à en-dessous de 70
      if(previousRSI >= RSIOverbought && currentRSI < RSIOverbought) {
         symbol.rsiCrossedDown = true;
         rsiCrossedDown = true;
         if(ShowTradeLogs) {
            PrintFormat("[%s] RSI Reversal - Sell Signal: Previous: %.2f >= %d, Current: %.2f < %d", 
                       symbol.symbol, previousRSI, RSIOverbought, currentRSI, RSIOverbought);
         }
      }
   } else {
      // Logique de continuation (Continuation)
      // Signal d'achat quand le RSI passe de en-dessous 70 à au-dessus de 70
      if(previousRSI <= RSIOverbought && currentRSI > RSIOverbought) {
         symbol.rsiCrossedUp = true;
         rsiCrossedUp = true;
         if(ShowTradeLogs) {
            PrintFormat("[%s] RSI Continuation - Buy Signal: Previous: %.2f <= %d, Current: %.2f > %d", 
                       symbol.symbol, previousRSI, RSIOverbought, currentRSI, RSIOverbought);
         }
      }
      
      // Signal de vente quand le RSI passe de au-dessus 30 à en-dessous de 30
      if(previousRSI >= RSIOversold && currentRSI < RSIOversold) {
         symbol.rsiCrossedDown = true;
         rsiCrossedDown = true;
         if(ShowTradeLogs) {
            PrintFormat("[%s] RSI Continuation - Sell Signal: Previous: %.2f >= %d, Current: %.2f < %d", 
                       symbol.symbol, previousRSI, RSIOversold, currentRSI, RSIOversold);
         }
      }
   }
   
   // Log des conditions de trading
   if(ShowTradeLogs) {
      PrintFormat("[%s] Trading Conditions - RSI Crossed Up: %s, RSI Crossed Down: %s, Current RSI: %.2f", 
                 symbol.symbol,
                 rsiCrossedUp ? "true" : "false",
                 rsiCrossedDown ? "true" : "false",
                 currentRSI);
   }
   
   // Check for new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(symbol.symbol, PERIOD_CURRENT, 0);
   
   // Vérifier les conditions EMA si le filtre est activé
   bool emaCondition = true;
   if(UseEMAFilter) {
      double emaBuffer[];
      double emaFastBuffer[];
      ArraySetAsSeries(emaBuffer, true);
      ArraySetAsSeries(emaFastBuffer, true);
      
      if(CopyBuffer(symbol.emaHandle, 0, 0, 1, emaBuffer) > 0 && 
         CopyBuffer(symbol.emaFastHandle, 0, 0, 1, emaFastBuffer) > 0) {
         
         double currentEMA = emaBuffer[0];
         double currentFastEMA = emaFastBuffer[0];
         symbol.lastEMA = currentEMA;
         symbol.lastFastEMA = currentFastEMA;
         
         // Conditions séparées pour Buy et Sell
         bool buyEMACondition = BuyAboveEMA ? 
            (currentBid > currentEMA) : 
            (currentBid < currentEMA);
            
         bool sellEMACondition = SellAboveEMA ? 
            (currentAsk > currentEMA) : 
            (currentAsk < currentEMA);
         
         // La condition EMA est vraie uniquement si la condition correspondante à la direction est respectée
         if(TradeDirection == TRADE_BUY) {
            emaCondition = buyEMACondition;
         } else if(TradeDirection == TRADE_SELL) {
            emaCondition = sellEMACondition;
         } else if(TradeDirection == TRADE_BOTH) {
            // For TRADE_BOTH, we need to check both conditions based on the trade type
            if(symbol.rsiCrossedUp) {
               emaCondition = buyEMACondition;
            } else if(symbol.rsiCrossedDown) {
               emaCondition = sellEMACondition;
            }
         }
         
         if(ShowTradeLogs) {
            PrintFormat("[%s] EMA Filter Active - Current Bid: %.5f, EMA: %.5f, Buy Condition: %s, Sell Condition: %s, Final Condition: %s", 
                      symbol.symbol, 
                      currentBid,
                      currentEMA,
                      buyEMACondition ? "true" : "false",
                      sellEMACondition ? "true" : "false",
                      emaCondition ? "true" : "false");
         }
      }
   } else {
      // Forcer emaCondition à true quand le filtre est désactivé
      emaCondition = true;
      if(ShowTradeLogs) {
         PrintFormat("[%s] EMA Filter Disabled - Trading without EMA conditions (emaCondition forced to true)", symbol.symbol);
      }
   }
   
   // Log supplémentaire pour confirmer l'état du filtre avant les conditions de trading
   if(ShowTradeLogs) {
      PrintFormat("[%s] Trading Conditions - RSI Crossed: %s, RSI Value: %.2f, EMA Condition: %s", 
                 symbol.symbol,
                 (symbol.rsiCrossedUp || symbol.rsiCrossedDown) ? "true" : "false",
                 currentRSI,
                 emaCondition ? "true" : "false");
   }
   
   if(currentBarTime != lastBarTime) {
      // New bar formed, check trading conditions
      
      // Buy conditions
      if(TradeDirection != TRADE_SELL && symbol.rsiCrossedUp && currentRSI > RSIOversold && emaCondition) {
         if(ShowTradeLogs) {
            PrintFormat("[%s] Buy Conditions Check - TradeDirection: %s, RSI Crossed Up: %s, Current RSI: %.2f > %d, EMA Condition: %s",
                       symbol.symbol,
                       TradeDirection != TRADE_SELL ? "true" : "false",
                       symbol.rsiCrossedUp ? "true" : "false",
                       currentRSI, RSIOversold,
                       emaCondition ? "true" : "false");
         }
         
         if(CountPositions(symbol.symbol, POSITION_TYPE_BUY) < MaxBuyPositions && 
            symbol.dailyTradesCount < MaxDailyTrades) {
            double lotSize = CalculateLotSize(symbol);
            if(lotSize > 0) {
               double sl = SymbolInfoDouble(symbol.symbol, SYMBOL_BID) - StopLoss * _Point;
               double tp = SymbolInfoDouble(symbol.symbol, SYMBOL_BID) + TakeProfit * _Point;
               
               if(UseWeightedExit && GroupByDirection) {
                  // Calculer le nouveau TP en fonction du prix moyen pondéré existant
                  double totalBuyLots = 0;
                  double weightedBuyPrice = 0;
                  
                  for(int i = PositionsTotal() - 1; i >= 0; i--) {
                     if(PositionSelectByTicket(PositionGetTicket(i))) {
                        if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                           PositionGetString(POSITION_SYMBOL) == symbol.symbol &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                           
                           double positionLots = PositionGetDouble(POSITION_VOLUME);
                           double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                           totalBuyLots += positionLots;
                           weightedBuyPrice += positionOpenPrice * positionLots;
                        }
                     }
                  }
                  
                  if(totalBuyLots > 0) {
                     weightedBuyPrice /= totalBuyLots;
                     tp = weightedBuyPrice + TakeProfit * _Point;
                  }
               }
               
               if(symbol.trade.Buy(lotSize, symbol.symbol, 0, sl, tp, "Buy Signal")) {
                  symbol.dailyTradesCount++;
                  symbol.lastTradeDate = currentTime;
                  if(ShowTradeLogs) {
                     PrintFormat("[%s] Buy trade opened. Daily trades: %d/%d", 
                               symbol.symbol, symbol.dailyTradesCount, MaxDailyTrades);
                  }
               }
               symbol.rsiCrossedUp = false;
            }
         }
      }
      
      // Sell conditions
      if(TradeDirection != TRADE_BUY && symbol.rsiCrossedDown && currentRSI < RSIOverbought && emaCondition) {
         if(ShowTradeLogs) {
            PrintFormat("[%s] Sell Conditions Check - TradeDirection: %s, RSI Crossed Down: %s, Current RSI: %.2f < %d, EMA Condition: %s",
                       symbol.symbol,
                       TradeDirection != TRADE_BUY ? "true" : "false",
                       symbol.rsiCrossedDown ? "true" : "false",
                       currentRSI, RSIOverbought,
                       emaCondition ? "true" : "false");
         }
         
         if(CountPositions(symbol.symbol, POSITION_TYPE_SELL) < MaxSellPositions && 
            symbol.dailyTradesCount < MaxDailyTrades) {
            double lotSize = CalculateLotSize(symbol);
            if(lotSize > 0) {
               double sl = SymbolInfoDouble(symbol.symbol, SYMBOL_ASK) + StopLoss * _Point;
               double tp = SymbolInfoDouble(symbol.symbol, SYMBOL_ASK) - TakeProfit * _Point;
               
               if(UseWeightedExit && GroupByDirection) {
                  // Calculer le nouveau TP en fonction du prix moyen pondéré existant
                  double totalSellLots = 0;
                  double weightedSellPrice = 0;
                  
                  for(int i = PositionsTotal() - 1; i >= 0; i--) {
                     if(PositionSelectByTicket(PositionGetTicket(i))) {
                        if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                           PositionGetString(POSITION_SYMBOL) == symbol.symbol &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                           
                           double positionLots = PositionGetDouble(POSITION_VOLUME);
                           double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                           totalSellLots += positionLots;
                           weightedSellPrice += positionOpenPrice * positionLots;
                        }
                     }
                  }
                  
                  if(totalSellLots > 0) {
                     weightedSellPrice /= totalSellLots;
                     tp = weightedSellPrice - TakeProfit * _Point;
                  }
               }
               
               if(symbol.trade.Sell(lotSize, symbol.symbol, 0, sl, tp, "Sell Signal")) {
                  symbol.dailyTradesCount++;
                  symbol.lastTradeDate = currentTime;
                  if(ShowTradeLogs) {
                     PrintFormat("[%s] Sell trade opened. Daily trades: %d/%d", 
                               symbol.symbol, symbol.dailyTradesCount, MaxDailyTrades);
                  }
               }
               symbol.rsiCrossedDown = false;
            }
         }
      }
      
      lastBarTime = currentBarTime;
   }
   
   // Update trailing stops
   UpdateTrailingStops(symbol);
}

//+------------------------------------------------------------------+
//| Calculate lot size for a position                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(SymbolData &symbol) {
   double lotSize = Lots;
   
   // Check if we need to increase lot size based on existing positions
   int buyPositions = CountPositions(symbol.symbol, POSITION_TYPE_BUY);
   int sellPositions = CountPositions(symbol.symbol, POSITION_TYPE_SELL);
   
   if(buyPositions > 0 || sellPositions > 0) {
      lotSize *= MathPow(LotMultiplier, buyPositions + sellPositions);
   }
   
   // Ensure lot size doesn't exceed maximum
   if(lotSize > MaxLot) {
      lotSize = MaxLot;
   }
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Update trailing stops for positions                                |
//+------------------------------------------------------------------+
void UpdateTrailingStops(SymbolData &symbol) {
   if(UseWeightedExit) {
      // Gestion pondérée des positions
      double totalBuyLots = 0;
      double totalSellLots = 0;
      double weightedBuyPrice = 0;
      double weightedSellPrice = 0;
      double totalBuyProfit = 0;
      double totalSellProfit = 0;
      
      // Calculer les prix moyens pondérés et les profits totaux
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetInteger(POSITION_MAGIC) == Magic && 
               PositionGetString(POSITION_SYMBOL) == symbol.symbol) {
               
               double positionLots = PositionGetDouble(POSITION_VOLUME);
               double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               double positionProfit = PositionGetDouble(POSITION_PROFIT);
               
               if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                  totalBuyLots += positionLots;
                  weightedBuyPrice += positionOpenPrice * positionLots;
                  totalBuyProfit += positionProfit;
               }
               else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                  totalSellLots += positionLots;
                  weightedSellPrice += positionOpenPrice * positionLots;
                  totalSellProfit += positionProfit;
               }
            }
         }
      }
      
      // Calculer les prix moyens pondérés
      if(totalBuyLots > 0) weightedBuyPrice /= totalBuyLots;
      if(totalSellLots > 0) weightedSellPrice /= totalSellLots;
      
      // Mettre à jour les trailing stops pour les positions Buy
      if(totalBuyLots > 0) {
         double currentBid = SymbolInfoDouble(symbol.symbol, SYMBOL_BID);
         double profitInPips = (currentBid - weightedBuyPrice) / _Point;
         
         if(profitInPips >= TralStart) {
            double newStopLoss = currentBid - Tral * _Point;
            
            // Mettre à jour toutes les positions Buy
            for(int i = PositionsTotal() - 1; i >= 0; i--) {
               if(PositionSelectByTicket(PositionGetTicket(i))) {
                  if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                     PositionGetString(POSITION_SYMBOL) == symbol.symbol &&
                     PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                     
                     double currentStopLoss = PositionGetDouble(POSITION_SL);
                     if(newStopLoss > currentStopLoss) {
                        symbol.trade.PositionModify(PositionGetTicket(i), newStopLoss, PositionGetDouble(POSITION_TP));
                     }
                  }
               }
            }
         }
      }
      
      // Mettre à jour les trailing stops pour les positions Sell
      if(totalSellLots > 0) {
         double currentAsk = SymbolInfoDouble(symbol.symbol, SYMBOL_ASK);
         double profitInPips = (weightedSellPrice - currentAsk) / _Point;
         
         if(profitInPips >= TralStart) {
            double newStopLoss = currentAsk + Tral * _Point;
            
            // Mettre à jour toutes les positions Sell
            for(int i = PositionsTotal() - 1; i >= 0; i--) {
               if(PositionSelectByTicket(PositionGetTicket(i))) {
                  if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                     PositionGetString(POSITION_SYMBOL) == symbol.symbol &&
                     PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                     
                     double currentStopLoss = PositionGetDouble(POSITION_SL);
                     if(newStopLoss < currentStopLoss || currentStopLoss == 0) {
                        symbol.trade.PositionModify(PositionGetTicket(i), newStopLoss, PositionGetDouble(POSITION_TP));
                     }
                  }
               }
            }
         }
      }
   }
   else {
      // Gestion individuelle des positions (code existant)
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetInteger(POSITION_MAGIC) == Magic && 
               PositionGetString(POSITION_SYMBOL) == symbol.symbol) {
               
               double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               double currentBid = SymbolInfoDouble(symbol.symbol, SYMBOL_BID);
               double currentAsk = SymbolInfoDouble(symbol.symbol, SYMBOL_ASK);
               double currentStopLoss = PositionGetDouble(POSITION_SL);
               
               if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                  double profitInPips = (currentBid - positionOpenPrice) / _Point;
                  
                  if(profitInPips >= TralStart) {
                     double newStopLoss = currentBid - Tral * _Point;
                     if(newStopLoss > currentStopLoss) {
                        symbol.trade.PositionModify(PositionGetTicket(i), newStopLoss, PositionGetDouble(POSITION_TP));
                     }
                  }
               }
               else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                  double profitInPips = (positionOpenPrice - currentAsk) / _Point;
                  
                  if(profitInPips >= TralStart) {
                     double newStopLoss = currentAsk + Tral * _Point;
                     if(newStopLoss < currentStopLoss || currentStopLoss == 0) {
                        symbol.trade.PositionModify(PositionGetTicket(i), newStopLoss, PositionGetDouble(POSITION_TP));
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update Position Cache for a specific symbol                        |
//+------------------------------------------------------------------+
void UpdatePositionCache(SymbolData &symbol) {
   datetime currentTime = TimeCurrent();
   
   if(!symbol.cacheNeedsUpdate && currentTime - symbol.lastCacheUpdate < cacheUpdateInterval) {
      return;
   }
   
   // Réinitialiser les valeurs
   symbol.cachedBuyProfit = 0;
   symbol.cachedSellProfit = 0;
   symbol.cachedBuyLots = 0;
   symbol.cachedSellLots = 0;
   symbol.cachedBuyPositions = 0;
   symbol.cachedSellPositions = 0;
   
   // Mettre à jour les valeurs
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == symbol.symbol) {
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               symbol.cachedBuyProfit += positionProfit;
               symbol.cachedBuyLots += positionLots;
               symbol.cachedBuyPositions++;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               symbol.cachedSellProfit += positionProfit;
               symbol.cachedSellLots += positionLots;
               symbol.cachedSellPositions++;
            }
         }
      }
   }
   
   symbol.lastCacheUpdate = currentTime;
   symbol.cacheNeedsUpdate = false;
}

//+------------------------------------------------------------------+
//| Count Positions for a specific symbol                              |
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
//| Update Info Panel                                                  |
//+------------------------------------------------------------------+
void UpdateInfoPanel() {
   if(!Info) return;
   
   // Mettre à jour le cache pour chaque paire
   for(int i = 0; i < ArraySize(symbols); i++) {
      UpdatePositionCache(symbols[i]);
   }

   string prefix = "EA_Info_";
   int x = 10;
   int y = 20;
   int yStep = FontSize + 10;
   int totalLines = 0;
   
   ObjectsDeleteAll(0, prefix);
   
   // Display EA status
   CreateLabel(prefix + "Title", "=== EA Status ===", x, y, TextColor);
   y += yStep;
   totalLines++;
   
   // Display daily trades info
   for(int i = 0; i < ArraySize(symbols); i++) {
      CreateLabel(prefix + "DailyTrades_" + symbols[i].symbol, 
                 StringFormat("%s: %d/%d trades today", 
                            symbols[i].symbol, 
                            symbols[i].dailyTradesCount, 
                            MaxDailyTrades), 
                 x, y, TextColor);
      y += yStep;
      totalLines++;
   }
   
   // Display current spread with dynamic color
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadInPips = spread / (_Point * 10);
   color spreadColor = GetDynamicColor(spreadInPips, MaxSpread, 0);
   CreateLabel(prefix + "Spread", StringFormat("Spread: %.1f pips", spreadInPips), x, y, spreadColor);
   y += yStep;
   totalLines++;
   
   // Display account information
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profit = equity - balance;
   double profitPercent = (profit / balance) * 100;
   
   CreateLabel(prefix + "Balance", StringFormat("Balance: %.2f", balance), x, y, TextColor);
   y += yStep;
   totalLines++;
   CreateLabel(prefix + "Equity", StringFormat("Equity: %.2f", equity), x, y, TextColor);
   y += yStep;
   totalLines++;
   CreateLabel(prefix + "Profit", StringFormat("Profit: %.2f (%.2f%%)", profit, profitPercent), 
              x, y, profit >= 0 ? clrLime : clrRed);
   y += yStep;
   totalLines++;
   
   // Create background rectangle with dynamic height
   int panelHeight = totalLines * yStep + 20; // 20 pixels de marge
   CreateRectangle(prefix + "Background", x - 5, 15, 300, panelHeight, clrBlack, 200);
}

//+------------------------------------------------------------------+
//| Create Label for Info Panel                                        |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr) {
   if(ObjectFind(0, name) != -1) {
      ObjectDelete(0, name);
   }
   
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
      PrintFormat("Error creating label: %d", GetLastError());
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
   
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Create Rectangle for Panel Background                              |
//+------------------------------------------------------------------+
void CreateRectangle(string name, int x, int y, int width, int height, color clr, int transparency) {
   if(ObjectFind(0, name) != -1) {
      ObjectDelete(0, name);
   }
   
   if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0)) {
      PrintFormat("Error creating rectangle: %d", GetLastError());
      return;
   }
   
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//+------------------------------------------------------------------+
//| Get Dynamic Color based on value range                             |
//+------------------------------------------------------------------+
color GetDynamicColor(double value, double maxValue, double minValue) {
   if(value >= maxValue) return clrRed;
   if(value <= minValue) return clrRed;
   
   double range = maxValue - minValue;
   double position = (value - minValue) / range;
   
   if(position < 0.5) {
      // From red to yellow
      return clrYellow;
   } else {
      // From yellow to green
      return clrGreen;
   }
}

//+------------------------------------------------------------------+
//| Print Status Line                                                  |
//+------------------------------------------------------------------+
void PrintStatusLine() {
   // Get current prices
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (currentAsk - currentBid) / _Point / 10;  // Convert to pips
   
   // Get positions info
   int buyPositions = CountPositions(_Symbol, POSITION_TYPE_BUY);
   int sellPositions = CountPositions(_Symbol, POSITION_TYPE_SELL);
   double buyProfit = 0;
   double sellProfit = 0;
   double buyLots = 0;
   double sellLots = 0;
   
   // Calculate profits and lots
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               buyProfit += PositionGetDouble(POSITION_PROFIT);
               buyLots += positionLots;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               sellProfit += PositionGetDouble(POSITION_PROFIT);
               sellLots += positionLots;
            }
         }
      }
   }
   
   // Calculate drawdowns
   double buyDD = buyProfit < 0 ? MathAbs(buyProfit) / initialBalance * 100 : 0;
   double sellDD = sellProfit < 0 ? MathAbs(sellProfit) / initialBalance * 100 : 0;
   
   // Get indicators values
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   int rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE);
   CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer);
   double currentRSI = rsiBuffer[0];
   
   double emaBuffer[];
   double emaFastBuffer[];
   ArraySetAsSeries(emaBuffer, true);
   ArraySetAsSeries(emaFastBuffer, true);
   int emaHandle = iMA(_Symbol, PERIOD_CURRENT, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   int emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, EMAFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   CopyBuffer(emaHandle, 0, 0, 1, emaBuffer);
   CopyBuffer(emaFastHandle, 0, 0, 1, emaFastBuffer);
   double currentEMA = emaBuffer[0];
   double currentFastEMA = emaFastBuffer[0];
   
   // Print single line with all important info
   PrintFormat("Bid: %.5f | Buy: %d(%.2f/%.2f) [DD:%.2f%%] | Sell: %d(%.2f/%.2f) [DD:%.2f%%] | Spread: %.1f | RSI: %.1f | EMA: %.5f | FastEMA: %.5f",
         currentBid, 
         buyPositions, buyProfit, buyLots, buyDD,
         sellPositions, sellProfit, sellLots, sellDD,
         spread,
         currentRSI,
         currentEMA,
         currentFastEMA);
} 