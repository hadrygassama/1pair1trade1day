//+------------------------------------------------------------------+
//|                                                           Scalper.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

// Enum pour la direction du trading
enum ENUM_TRADE_DIRECTION {
   TRADE_BUY_ONLY,      // Buy Only
   TRADE_SELL_ONLY,     // Sell Only
   TRADE_BOTH           // Buy and Sell
};

// Expert parameters
input group    "=== Trading Settings ==="
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Trade Direction
input int      Magic = 123456;         // Numéro magique
input double   Lots = 0.1;             // Taille des lots
input int      OpenTime = 60;          // Temps entre les ordres (secondes)
input int      TimeStart = 0;          // Heure de début du trading
input int      TimeEnd = 23;           // Heure de fin du trading
input int      MaxSpread = 40;         // Spread maximum (en pips)
input int      PipsStep = 25;          // Pas pour le mouvement de prix (en pips)

input group    "=== Stop Loss/Take Profit Settings ==="
input int      Tral = 30;             // Trailing stop (en pips)
input int      TralStart = 10;        // Début du trailing (en pips)
input double   TakeProfit = 25;       // Take Profit (en pips)

input group    "=== Interface Settings ==="
input bool     Info = true;            // Afficher le panneau d'information
input int      FontSize = 12;          // Taille de la police du panneau
input color    TextColor = clrWhite;   // Couleur du texte

// Global variables
CTrade trade;
string expertName = "Scalper";
datetime lastOpenTime = 0;
double lastBidPrice = 0;
double initialBalance = 0;
double maxBuyDD = 0;
double maxSellDD = 0;
double maxTotalDD = 0;
double totalPriceMovement = 0;  // Nouvelle variable pour suivre le mouvement total

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(Magic);
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   maxBuyDD = 0;
   maxSellDD = 0;
   maxTotalDD = 0;
   
   Print("EA initialized - Magic: ", Magic);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "EA_Info_");
   Print("EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
   // Update panel first
   if(Info) UpdateInfoPanel();
   
   // Check trading hours
   datetime currentTime = TimeCurrent();
   MqlDateTime timeStruct;
   TimeToStruct(currentTime, timeStruct);
   if(timeStruct.hour < TimeStart || timeStruct.hour >= TimeEnd) {
      Print("Outside trading hours: ", timeStruct.hour, " (Start: ", TimeStart, ", End: ", TimeEnd, ")");
      return;
   }
   
   // Check spread
   double currentSpread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadInPips = currentSpread / (_Point * 10);  // Convertir en pips (1 pip = 10 points)
   Print("Current Spread: ", currentSpread, " (", spreadInPips, " pips)");
   if(spreadInPips > MaxSpread) {
      Print("Spread too high: ", spreadInPips, " pips > ", MaxSpread, " pips");
      return;
   }
   
   // Initialize trade conditions
   bool canOpenBuy = false;
   bool canOpenSell = false;
   
   // Check time conditions for new trades
   if(lastOpenTime == 0) {
      lastOpenTime = currentTime;
      lastBidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      totalPriceMovement = 0;
      Print("First tick - Initializing lastOpenTime and lastBidPrice");
   }
   
   // Check price movements for new trades
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double priceMovement = MathAbs(currentBid - lastBidPrice) / (_Point * 10);  // Mouvement en pips
   totalPriceMovement += priceMovement;
   Print("Current Bid: ", currentBid, ", Last Bid: ", lastBidPrice, ", Movement: ", priceMovement, " pips, Total Movement: ", totalPriceMovement, " pips, Required: ", PipsStep, " pips");
   
   // Vérifier les conditions en fonction de la direction choisie
   if(TradeDirection == TRADE_BUY_ONLY || TradeDirection == TRADE_BOTH) {
      if(currentBid > lastBidPrice && totalPriceMovement >= PipsStep) {
         canOpenBuy = true;
         Print("Buy condition met - Price moved up by ", totalPriceMovement, " pips");
      }
   }
   
   if(TradeDirection == TRADE_SELL_ONLY || TradeDirection == TRADE_BOTH) {
      if(currentBid < lastBidPrice && totalPriceMovement >= PipsStep) {
         canOpenSell = true;
         Print("Sell condition met - Price moved down by ", totalPriceMovement, " pips");
      }
   }
   
   // Open new trades if conditions are met
   if(canOpenBuy) {
      OpenBuyOrder();
      lastBidPrice = currentBid;  // Mettre à jour lastBidPrice uniquement après un trade
      totalPriceMovement = 0;     // Réinitialiser le mouvement total
      lastOpenTime = currentTime; // Mettre à jour le temps du dernier trade
   }
   if(canOpenSell) {
      OpenSellOrder();
      lastBidPrice = currentBid;  // Mettre à jour lastBidPrice uniquement après un trade
      totalPriceMovement = 0;     // Réinitialiser le mouvement total
      lastOpenTime = currentTime; // Mettre à jour le temps du dernier trade
   }
   
   // Update trailing stops and check take profits
   UpdateTrailingStops();
   
   // Check DCA conditions only for allowed directions
   CheckDCAConditions();
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder() {
   // Vérifier si les Buy sont autorisés
   if(TradeDirection == TRADE_SELL_ONLY) return;
   
   int totalBuyPositions = CountPositions(POSITION_TYPE_BUY);
   
   if(totalBuyPositions < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2) {
      int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_BUY);
      
      if(positionsInCurrentBar == 0) {
         if(!trade.Buy(Lots, _Symbol, 0, 0, 0, expertName)) {
            Print("Buy order failed. Error: ", GetLastError());
         }
         else {
            Print("Buy order placed successfully with lots: ", Lots);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                    |
//+------------------------------------------------------------------+
void OpenSellOrder() {
   // Vérifier si les Sell sont autorisés
   if(TradeDirection == TRADE_BUY_ONLY) return;
   
   int totalSellPositions = CountPositions(POSITION_TYPE_SELL);
   
   if(totalSellPositions < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2) {
      int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_SELL);
      
      if(positionsInCurrentBar == 0) {
         if(!trade.Sell(Lots, _Symbol, 0, 0, 0, expertName)) {
            Print("Sell order failed. Error: ", GetLastError());
         }
         else {
            Print("Sell order placed successfully with lots: ", Lots);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count Positions                                                    |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE positionType) {
   int count = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
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
int CountPositionsInCurrentBar(ENUM_POSITION_TYPE positionType) {
   int count = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
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
void UpdateTrailingStops() {
   // Variables pour les positions Buy
   double buyTotalProfit = 0;
   double buyAveragePrice = 0;
   int buyPositionCount = 0;
   double buyTotalLots = 0;
   
   // Variables pour les positions Sell
   double sellTotalProfit = 0;
   double sellAveragePrice = 0;
   int sellPositionCount = 0;
   double sellTotalLots = 0;
   
   // Premier passage : calcul des moyennes et profits
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               buyTotalProfit += positionProfit;
               buyAveragePrice += openPrice * positionLots;
               buyTotalLots += positionLots;
               buyPositionCount++;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               sellTotalProfit += positionProfit;
               sellAveragePrice += openPrice * positionLots;
               sellTotalLots += positionLots;
               sellPositionCount++;
            }
         }
      }
   }
   
   // Calcul des prix moyens pondérés par les lots
   if(buyPositionCount > 0) buyAveragePrice /= buyTotalLots;
   if(sellPositionCount > 0) sellAveragePrice /= sellTotalLots;
   
   // Gestion des profits et trailing stops
   if(buyPositionCount > 0) {
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double buyProfitInPoints = (currentBid - buyAveragePrice) / _Point;
      
      // Vérifier si le groupe Buy a atteint le take profit
      if(buyProfitInPoints >= TakeProfit) {
         Print("Closing all Buy positions - Total profit in points: ", buyProfitInPoints);
         ClosePositionsInDirection(POSITION_TYPE_BUY);
      } else {
         // Mise à jour des trailing stops pour toutes les positions Buy
         if(Tral != 0) {
            for(int i = PositionsTotal() - 1; i >= 0; i--) {
               if(PositionSelectByTicket(PositionGetTicket(i))) {
                  if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                     PositionGetString(POSITION_SYMBOL) == _Symbol &&
                     PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                     
                     double currentSL = PositionGetDouble(POSITION_SL);
                     
                     if(currentSL < buyAveragePrice || currentSL == 0) {
                        if(currentBid - (Tral + TralStart) * _Point >= buyAveragePrice) {
                           trade.PositionModify(PositionGetTicket(i),
                                              buyAveragePrice + TralStart * _Point,
                                              PositionGetDouble(POSITION_TP));
                        }
                     }
                     else if(currentSL >= buyAveragePrice) {
                        if(currentBid - Tral * _Point > currentSL) {
                           trade.PositionModify(PositionGetTicket(i),
                                              currentBid - Tral * _Point,
                                              PositionGetDouble(POSITION_TP));
                        }
                     }
                  }
               }
            }
         }
      }
   }
   
   if(sellPositionCount > 0) {
      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sellProfitInPoints = (sellAveragePrice - currentAsk) / _Point;
      
      // Vérifier si le groupe Sell a atteint le take profit
      if(sellProfitInPoints >= TakeProfit) {
         Print("Closing all Sell positions - Total profit in points: ", sellProfitInPoints);
         ClosePositionsInDirection(POSITION_TYPE_SELL);
      } else {
         // Mise à jour des trailing stops pour toutes les positions Sell
         if(Tral != 0) {
            for(int i = PositionsTotal() - 1; i >= 0; i--) {
               if(PositionSelectByTicket(PositionGetTicket(i))) {
                  if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                     PositionGetString(POSITION_SYMBOL) == _Symbol &&
                     PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                     
                     double currentSL = PositionGetDouble(POSITION_SL);
                     
                     if(currentSL > sellAveragePrice || currentSL == 0) {
                        if(currentAsk + (Tral + TralStart) * _Point <= sellAveragePrice) {
                           trade.PositionModify(PositionGetTicket(i),
                                              sellAveragePrice - TralStart * _Point,
                                              PositionGetDouble(POSITION_TP));
                        }
                     }
                     else if(currentSL <= sellAveragePrice) {
                        if(currentAsk + Tral * _Point < currentSL) {
                           trade.PositionModify(PositionGetTicket(i),
                                              currentAsk + Tral * _Point,
                                              PositionGetDouble(POSITION_TP));
                        }
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
void ClosePositionsInDirection(ENUM_POSITION_TYPE positionType) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_TYPE) == positionType) {
            trade.PositionClose(PositionGetTicket(i));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check DCA Conditions                                              |
//+------------------------------------------------------------------+
void CheckDCAConditions() {
   // Variables pour Buy
   double buyAveragePrice = 0;
   double buyTotalLots = 0;
   int buyPositionCount = 0;
   
   // Variables pour Sell
   double sellAveragePrice = 0;
   double sellTotalLots = 0;
   int sellPositionCount = 0;
   
   // Calcul des moyennes pour Buy et Sell séparément
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               buyAveragePrice += openPrice * positionLots;
               buyTotalLots += positionLots;
               buyPositionCount++;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               sellAveragePrice += openPrice * positionLots;
               sellTotalLots += positionLots;
               sellPositionCount++;
            }
         }
      }
   }
   
   // Calcul des prix moyens pondérés
   if(buyTotalLots > 0) buyAveragePrice /= buyTotalLots;
   if(sellTotalLots > 0) sellAveragePrice /= sellTotalLots;
   
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Vérifier les conditions DCA pour Buy si autorisé
   if(TradeDirection != TRADE_SELL_ONLY && buyPositionCount > 0) {
      if(currentBid + PipsStep * _Point <= buyAveragePrice && 
         buyPositionCount < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2) {
         
         int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_BUY);
         if(positionsInCurrentBar == 0) {
            Print("DCA Buy condition met - Price dropped below average by ", PipsStep, " pips");
            OpenBuyOrder();
         }
      }
   }
   
   // Vérifier les conditions DCA pour Sell si autorisé
   if(TradeDirection != TRADE_BUY_ONLY && sellPositionCount > 0) {
      if(currentAsk - PipsStep * _Point >= sellAveragePrice && 
         sellPositionCount < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2) {
         
         int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_SELL);
         if(positionsInCurrentBar == 0) {
            Print("DCA Sell condition met - Price rose above average by ", PipsStep, " pips");
            OpenSellOrder();
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
   int x = 20;  // Distance from right border
   int y = 20;  // Distance from top border
   int yStep = FontSize + 10;  // Espacement vertical basé sur la taille de la police
   
   ObjectsDeleteAll(0, prefix);
   
   // Display EA status
   CreateLabel(prefix + "Title", "=== EA Status ===", x, y, TextColor);
   y += yStep;
   
   // Display current spread
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spreadInPips = spread / (_Point * 10);
   CreateLabel(prefix + "Spread", StringFormat("Spread: %.1f pips", spreadInPips), x, y, TextColor);
   y += yStep;
   
   // Calculate positions info
   int totalBuyPositions = CountPositions(POSITION_TYPE_BUY);
   int totalSellPositions = CountPositions(POSITION_TYPE_SELL);
   double buyTotalProfit = 0;
   double sellTotalProfit = 0;
   double buyAveragePrice = 0;
   double sellAveragePrice = 0;
   double buyTotalLots = 0;
   double sellTotalLots = 0;
   
   // Calculate profits and averages
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i))) {
         if(PositionGetInteger(POSITION_MAGIC) == Magic && 
            PositionGetString(POSITION_SYMBOL) == _Symbol) {
            
            double positionLots = PositionGetDouble(POSITION_VOLUME);
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
               buyTotalProfit += PositionGetDouble(POSITION_PROFIT);
               buyAveragePrice += PositionGetDouble(POSITION_PRICE_OPEN) * positionLots;
               buyTotalLots += positionLots;
            }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
               sellTotalProfit += PositionGetDouble(POSITION_PROFIT);
               sellAveragePrice += PositionGetDouble(POSITION_PRICE_OPEN) * positionLots;
               sellTotalLots += positionLots;
            }
         }
      }
   }
   
   // Calculate average prices
   if(buyTotalLots > 0) buyAveragePrice /= buyTotalLots;
   if(sellTotalLots > 0) sellAveragePrice /= sellTotalLots;
   
   // Calculate drawdowns
   double currentBuyDD = 0;
   double currentSellDD = 0;
   
   if(buyTotalProfit < 0) {
      currentBuyDD = MathAbs(buyTotalProfit) / initialBalance * 100;
      maxBuyDD = MathMax(maxBuyDD, currentBuyDD);
   }
   
   if(sellTotalProfit < 0) {
      currentSellDD = MathAbs(sellTotalProfit) / initialBalance * 100;
      maxSellDD = MathMax(maxSellDD, currentSellDD);
   }
   
   // Calculate total drawdown
   double totalProfit = buyTotalProfit + sellTotalProfit;
   double currentTotalDD = 0;
   
   if(totalProfit < 0) {
      currentTotalDD = MathAbs(totalProfit) / initialBalance * 100;
      maxTotalDD = MathMax(maxTotalDD, currentTotalDD);
   }
   
   // Display Buy information
   CreateLabel(prefix + "BuyPositions", StringFormat("Buy Positions: %d (%.2f lots)", totalBuyPositions, buyTotalLots), x, y, clrLime);
   y += yStep;
   if(totalBuyPositions > 0) {
      CreateLabel(prefix + "BuyProfit", StringFormat("Buy Profit: %.2f", buyTotalProfit), x, y, clrLime);
      y += yStep;
      CreateLabel(prefix + "BuyAverage", StringFormat("Buy Avg Price: %.5f", buyAveragePrice), x, y, clrLime);
      y += yStep;
      CreateLabel(prefix + "BuyDD", StringFormat("Buy DD: %.2f%% (Max: %.2f%%)", currentBuyDD, maxBuyDD), x, y, 
                 currentBuyDD > 0 ? clrOrange : clrLime);
      y += yStep;
   }
   
   // Display Sell information
   CreateLabel(prefix + "SellPositions", StringFormat("Sell Positions: %d (%.2f lots)", totalSellPositions, sellTotalLots), x, y, clrRed);
   y += yStep;
   if(totalSellPositions > 0) {
      CreateLabel(prefix + "SellProfit", StringFormat("Sell Profit: %.2f", sellTotalProfit), x, y, clrRed);
      y += yStep;
      CreateLabel(prefix + "SellAverage", StringFormat("Sell Avg Price: %.5f", sellAveragePrice), x, y, clrRed);
      y += yStep;
      CreateLabel(prefix + "SellDD", StringFormat("Sell DD: %.2f%% (Max: %.2f%%)", currentSellDD, maxSellDD), x, y, 
                 currentSellDD > 0 ? clrOrange : clrRed);
      y += yStep;
   }
   
   // Display total information
   y += yStep;
   int totalPositions = totalBuyPositions + totalSellPositions;
   double totalLots = buyTotalLots + sellTotalLots;
   CreateLabel(prefix + "TotalPositions", StringFormat("Total Positions: %d (%.2f lots)", totalPositions, totalLots), x, y, TextColor);
   y += yStep;
   CreateLabel(prefix + "TotalProfit", StringFormat("Total Profit: %.2f", totalProfit), x, y, TextColor);
   y += yStep;
   CreateLabel(prefix + "TotalDD", StringFormat("Total DD: %.2f%% (Max: %.2f%%)", currentTotalDD, maxTotalDD), x, y, 
              currentTotalDD > 0 ? clrOrange : TextColor);
   y += yStep;
   
   // Display next trade time
   datetime currentTime = TimeCurrent();
   if(lastOpenTime > 0) {
      datetime nextOpenTime = lastOpenTime + OpenTime;
      if(nextOpenTime > currentTime) {
         CreateLabel(prefix + "NextTrade", StringFormat("Next Trade: %s", 
                    TimeToString(nextOpenTime, TIME_MINUTES|TIME_SECONDS)), x, y, TextColor);
      }
   }
}

//+------------------------------------------------------------------+
//| Create Label for Info Panel                                        |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr) {
   if(ObjectFind(0, name) != -1) {
      ObjectDelete(0, name);
   }
   
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) {
      Print("Error creating label: ", GetLastError());
      return;
   }
   
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
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

