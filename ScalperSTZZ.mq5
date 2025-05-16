//+------------------------------------------------------------------+
//|                                                    ScalperSTZZ.mq5 |
//|                                                                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Includes                                                           |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                       |
//+------------------------------------------------------------------+
enum ENUM_LOT_TYPE
{
    LOT_TYPE_FIXED = 0,    // Fixed lot size
    LOT_TYPE_CURRENCY = 1  // Currency-based lot size
};

enum ENUM_TRADE_DIRECTION {
   TRADE_BUY_ONLY,      // Buy Only
   TRADE_SELL_ONLY,     // Sell Only
   TRADE_BOTH           // Buy and Sell
};

enum ENUM_PRICE_CONDITION {
    PRICE_CONDITION_BOTH = 0,         // Trade above and below
    PRICE_CONDITION_ABOVE_BELOW = 1   // Trade only above buy and Trade only below sell
};

enum ENUM_SUPERTREND_MODE
{
    SUPERTREND_DISABLED = 0,           // Disable Supertrend Filter
    SUPERTREND_FILTER_AND_CLOSE = 1,   // Supertrend Filter & Close on change
    SUPERTREND_FILTER_ONLY = 2         // Supertrend Filter Only
};

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
// === Basic Settings ===
input group "=== Basic Settings ==="
input int      Magic = 548762;         // Magic Number

// === Indicator Settings ===
input group "=== Supertrend Settings ==="
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;  // Timeframe
input int    ATR_Period = 10;        // ATR Period
input double ATR_Multiplier = 10.0;   // ATR Multiplier

// === Trading Settings ===
input group "=== Trading Settings ==="
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Trade Direction
input ENUM_LOT_TYPE LotType = LOT_TYPE_CURRENCY;  // Lot size type
input double LotSize = 0.1;          // Fixed lot size
input double CurrencyAmount = 10000;  // Amount per lot (in account currency)
input double BaseLot = 0.01;         // Base lot size for currency amount
input double RiskPercent = 1;      // Risk percentage per trade
input ENUM_SUPERTREND_MODE SupertrendMode = SUPERTREND_FILTER_ONLY;  // Supertrend Mode
input ENUM_PRICE_CONDITION PriceCondition = PRICE_CONDITION_BOTH;  // Price condition for entries

// === Trading Limits ===
input group "=== Trading Limits ==="
input int      MaxDailyBuyTrades = 0;    // Max daily buy trades (0=unlimited)
input int      MaxDailySellTrades = 0;   // Max daily sell trades (0=unlimited)
input int      MaxDailyTrades = 0;       // Max total daily trades (0=unlimited)
input int      MaxBuyTrades = 0;         // Max buy trades (0=unlimited)
input int      MaxSellTrades = 0;        // Max sell trades (0=unlimited)
input int      MaxTrades = 0;            // Max total trades (0=unlimited)
input double   DailyTargetCurrency = 0.0;  // Daily Target (Currency, 0=disabled)
input double   DailyTargetPercent = 0.0;   // Daily Target (Percent, 0=disabled)
input double   DailyLossCurrency = 0.0;    // Daily Loss (Currency, 0=disabled)
input double   DailyLossPercent = 0.0;     // Daily Loss (Percent, 0=disabled)

// === Order Management ===
input group "=== Order Management ==="
input int      FixedTP = 0;       // Take Profit (points, 0=disabled)
input int      FixedSL = 0;          // Stop Loss (points, 0=disabled)
input int      OpenTime = 1;          // Time between orders (seconds)
input int      PipsStep = 1;          // Price movement step (in pips)

// === Trailing Stop Settings ===
input group "=== Trailing Stop Settings ==="
input int      Tral = 20;             // Trailing stop (in pips, 0=disabled)
input int      TralStart = 10;        // Trailing start (in pips, 0=disabled)
input double   TakeProfit = 30;       // Take Profit (in pips, 0=disabled)

// === Trading Hours ===
input group "=== Trading Hours ==="
input int      TimeStartHour = 0;      // Start hour
input int      TimeStartMinute = 0;    // Start minute
input int      TimeEndHour = 23;       // End hour
input int      TimeEndMinute = 59;     // End minute
input bool     AutoDetectBrokerOffset = false;  // Auto-detect GMT offset
input bool     BrokerIsAheadOfGMT = true;       // Broker ahead of GMT
input int      ManualBrokerOffset = 3;          // Manual GMT offset (hours)

// === Spread and Slippage ===
input group "=== Spread and Slippage ==="
input int      MaxSpread = 1000;         // Max spread (pips)
input int      Slippage = 3;           // Slippage (points)

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
CTrade trade;                         // Trading object
string CurrentSymbol;                 // Current symbol
int stHandle;                         // Supertrend indicator handle
int totalBars;                        // Total number of bars
double lotSize;                       // Lot size

// Scalper variables
datetime lastOpenTime = 0;
double lastBidPrice = 0;
double lastBuyPrice = 0;    // Dernier prix d'achat
double lastSellPrice = 0;   // Dernier prix de vente

// Trading limits variables
datetime lastCalculationTime = 0;
int lastDealsCount = 0;
int lastPositionsCount = 0;
double lastCalculatedProfit = 0.0;

// Logging variables
datetime lastLogTime = 0;
int logInterval = 5;  // Intervalle minimum entre les logs en secondes
bool logErrors = true;            // Log des erreurs

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Test message at startup
    Print("=== ScalperSTZZ Initialization ===");
    Print("Current Symbol: ", Symbol());
    Print("Trading Hours: ", TimeStartHour, ":", TimeStartMinute, " - ", TimeEndHour, ":", TimeEndMinute);
    
    // Initialize current symbol
    CurrentSymbol = Symbol();
    
    // Check if symbol is valid
    if(!SymbolSelect(CurrentSymbol, true))
    {
        Print("Error: Symbol " + CurrentSymbol + " not available");
        return(INIT_FAILED);
    }
    
    // Set trading parameters
    trade.SetExpertMagicNumber(Magic);
    trade.SetDeviationInPoints(Slippage);
    
    // Check if enough bars are available
    if(iBars(CurrentSymbol, Timeframe) < ATR_Period + 1)
    {
        Print("Error: Not enough bars for " + CurrentSymbol);
        return(INIT_FAILED);
    }
    
    // Initialize indicators
    stHandle = iCustom(CurrentSymbol, Timeframe, "SupertrendIndicator.ex5", ATR_Period, ATR_Multiplier);
    
    if(stHandle == INVALID_HANDLE)
    {
        Print("Error initializing Supertrend indicator for " + CurrentSymbol + ". Error code: " + IntegerToString(GetLastError()));
        return(INIT_FAILED);
    }
    
    totalBars = iBars(CurrentSymbol, Timeframe);
    lotSize = LotSize;
    
    // Enable timer for reliable bar detection
    EventSetTimer(1);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(stHandle != INVALID_HANDLE)
        IndicatorRelease(stHandle);
    EventKillTimer();
    
}

//+------------------------------------------------------------------+
//| Timer function for processing trading logic                        |
//+------------------------------------------------------------------+
void OnTimer()
{
    if(!IsWithinTradingHours())
        return;
        
    // Vérifier si l'objectif quotidien est atteint
    if(IsDailyTargetReached())
    {
        CloseAllBuyPositions();
        CloseAllSellPositions();
        return;
    }
    
    // Vérifier si le spread est acceptable
    double currentSpread = SymbolInfoInteger(CurrentSymbol, SYMBOL_SPREAD) * Point();
    if(currentSpread > MaxSpread)
    {
        return;
    }
    
    // Vérifier si le trading est autorisé
    if(!IsTradeAllowed(true))
    {
        return;
    }
        
    int bars = iBars(CurrentSymbol, Timeframe);
    if(totalBars != bars)
    {
        totalBars = bars;
        
        double st[], zigzag[], zigzagHighLow[];
        ArrayResize(st, 3);
        ArrayResize(zigzag, 3);
        ArrayResize(zigzagHighLow, 3);
        ArraySetAsSeries(st, true);
        
        // Copy Supertrend buffer with retry
        int maxRetries = 5;
        int retryDelay = 100; // milliseconds
        int copied = 0;
        
        for(int retry = 0; retry < maxRetries; retry++)
        {
            copied = CopyBuffer(stHandle, 0, 0, 3, st);
            if(copied > 0) break;
            Sleep(retryDelay);
        }
        
        if(copied <= 0)
        {
            Print("Error copying Supertrend buffer. Error code: " + IntegerToString(GetLastError()));
            return;
        }
        
        // Copy ZigZag main buffer with retry
        copied = 0;
        for(int retry = 0; retry < maxRetries; retry++)
        {
            copied = CopyBuffer(zzHandle, 0, 0, 3, zigzag);
            if(copied > 0) break;
            Sleep(retryDelay);
        }
        
        if(copied <= 0)
        {
            Print("Error copying ZigZag buffer. Error code: " + IntegerToString(GetLastError()));
            return;
        }
        
        // Copy ZigZag HighLow buffer with retry
        copied = 0;
        for(int retry = 0; retry < maxRetries; retry++)
        {
            copied = CopyBuffer(zzHandle, 1, 0, 3, zigzagHighLow);
            if(copied > 0) break;
            Sleep(retryDelay);
        }
        
        if(copied <= 0)
        {
            Print("Error copying ZigZag HighLow buffer. Error code: " + IntegerToString(GetLastError()));
            return;
        }
        
        double close1 = iClose(CurrentSymbol, Timeframe, 1);
        double close2 = iClose(CurrentSymbol, Timeframe, 2);
        
        if(close1 == 0 || close2 == 0)
        {
            Print("Error getting close prices");
            return;
        }
        
        // Gérer les trailing stops
        HandleTrailingStopsScalper();
        
        // Mise à jour des niveaux ZigZag
        if(zigzagHighLow[0] != 0.0)
        {
            if(lastZigZagHigh != zigzag[0] && zigzag[0] != 0.0)
            {
                previousZigZagHigh = lastZigZagHigh;
                lastZigZagHigh = zigzag[0];
            }
        }
        else
        {
            if(lastZigZagLow != zigzag[0] && zigzag[0] != 0.0)
            {
                previousZigZagLow = lastZigZagLow;
                lastZigZagLow = zigzag[0];
            }
        }
        
        // Vérifier la tendance Supertrend
        bool isSupertrendBullish = close1 > st[1];
        bool isSupertrendBearish = close1 < st[1];
        
        // Vérifier les conditions d'entrée une seule fois
        bool canTrade = CheckScalperEntryConditions(st, close1);
        
        // Gérer les positions existantes
        ManagePositions();
        
        // Ouvrir de nouvelles positions si les conditions sont remplies
        if(canTrade && IsTradeAllowed(true))
        {
            if(SupertrendMode == SUPERTREND_DISABLED || 
               (SupertrendMode != SUPERTREND_DISABLED && isSupertrendBullish))
            {
                OpenPosition(true);
            }
            else if(SupertrendMode == SUPERTREND_DISABLED || 
                    (SupertrendMode != SUPERTREND_DISABLED && isSupertrendBearish))
            {
                OpenPosition(false);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check Scalper Entry Conditions                                     |
//+------------------------------------------------------------------+
bool CheckScalperEntryConditions(double &st[], double close1)
{
    // Check time conditions for new trades
    datetime currentTime = TimeCurrent();
    if(lastOpenTime == 0)
    {
        lastOpenTime = currentTime;
        lastBidPrice = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
        return false;
    }
    
    // Check time between trades only if OpenTime > 0
    if(OpenTime > 0 && currentTime - lastOpenTime < OpenTime)
    {
        return false;
    }
    
    // Check price movements for new trades
    double currentBid = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);
    
    // Vérifier la tendance Supertrend
    bool isSupertrendBullish = close1 > st[1];
    bool isSupertrendBearish = close1 < st[1];
    
    // Appliquer le filtre Supertrend selon le mode choisi
    if(SupertrendMode != SUPERTREND_DISABLED)
    {
        // Réinitialiser les prix de référence lors d'un changement de tendance
        if(isSupertrendBullish && lastBuyPrice == 0)
        {
            lastSellPrice = 0; // Réinitialiser le prix de vente pour permettre de nouveaux achats
        }
        else if(isSupertrendBearish && lastSellPrice == 0)
        {
            lastBuyPrice = 0; // Réinitialiser le prix d'achat pour permettre de nouvelles ventes
        }
    }
    
    // Vérifier si le trading est autorisé dans la direction actuelle
    if(TradeDirection == TRADE_BUY_ONLY || TradeDirection == TRADE_BOTH)
    {
        // Pour les achats, vérifier les conditions de prix
        bool canBuy = false;
        
        switch(PriceCondition)
        {
            case PRICE_CONDITION_BOTH:
                // Pour les achats, on peut acheter si :
                // 1. C'est le premier achat (lastBuyPrice == 0)
                // 2. Le prix actuel est inférieur au dernier prix d'achat de PipsStep pips
                // 3. Le prix actuel est supérieur au dernier prix de vente de PipsStep pips
                canBuy = (lastBuyPrice == 0 || 
                         (currentAsk <= lastBuyPrice - PipsStep * _Point &&
                          (lastSellPrice == 0 || currentAsk >= lastSellPrice + PipsStep * _Point)));
                break;
                
            case PRICE_CONDITION_ABOVE_BELOW:
                // Pour les achats en mode ABOVE_BELOW, on achète uniquement si le prix est au-dessus
                canBuy = (lastBuyPrice == 0 || currentAsk >= lastBuyPrice + PipsStep * _Point);
                break;
        }
        
        if(canBuy)
        {
            lastBidPrice = currentBid;
            lastOpenTime = currentTime;
            return true;
        }
    }
    
    if(TradeDirection == TRADE_SELL_ONLY || TradeDirection == TRADE_BOTH)
    {
        // Pour les ventes, vérifier les conditions de prix
        bool canSell = false;
        
        switch(PriceCondition)
        {
            case PRICE_CONDITION_BOTH:
                // Pour les ventes, on peut vendre si :
                // 1. C'est la première vente (lastSellPrice == 0)
                // 2. Le prix actuel est supérieur au dernier prix de vente de PipsStep pips
                // 3. Le prix actuel est inférieur au dernier prix d'achat de PipsStep pips
                canSell = (lastSellPrice == 0 || 
                          (currentBid >= lastSellPrice + PipsStep * _Point &&
                           (lastBuyPrice == 0 || currentBid <= lastBuyPrice - PipsStep * _Point)));
                break;
                
            case PRICE_CONDITION_ABOVE_BELOW:
                // Pour les ventes en mode ABOVE_BELOW, on vend uniquement si le prix est en-dessous
                canSell = (lastSellPrice == 0 || currentBid <= lastSellPrice - PipsStep * _Point);
                break;
        }
        
        if(canSell)
        {
            lastBidPrice = currentBid;
            lastOpenTime = currentTime;
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
    if(TradeDirection == TRADE_SELL_ONLY) {
        Print("OpenBuyOrder - Trading direction ne permet pas les achats", true);
        return;
    }
    
    int totalBuyPositions = CountPositions(POSITION_TYPE_BUY);
    
    if(totalBuyPositions < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2)
    {
        int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_BUY);
        
        if(positionsInCurrentBar == 0)
        {
            double sl = FixedSL > 0 ? NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK) - FixedSL * _Point, _Digits) : 0;
            double tp = FixedTP > 0 ? NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK) + FixedTP * _Point, _Digits) : 0;
            
            lotSize = CalculatePositionSize(sl, SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), true);
            
            if(!trade.Buy(lotSize, CurrentSymbol, 0, sl, tp, "Buy Order"))
            {
                Print("OpenBuyOrder - Échec de l'ordre. Erreur: " + IntegerToString(GetLastError()), true);
            }
            else
            {
                lastBuyPrice = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);
                Print("OpenBuyOrder - Nouveau prix d'achat: " + DoubleToString(lastBuyPrice, _Digits), true);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                    |
//+------------------------------------------------------------------+
void OpenSellOrder()
{
    if(TradeDirection == TRADE_BUY_ONLY) {
        Print("OpenSellOrder - Trading direction ne permet pas les ventes", true);
        return;
    }
    
    int totalSellPositions = CountPositions(POSITION_TYPE_SELL);
    
    if(totalSellPositions < AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) / 2)
    {
        int positionsInCurrentBar = CountPositionsInCurrentBar(POSITION_TYPE_SELL);
        
        if(positionsInCurrentBar == 0)
        {
            double sl = FixedSL > 0 ? NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID) + FixedSL * _Point, _Digits) : 0;
            double tp = FixedTP > 0 ? NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID) - FixedTP * _Point, _Digits) : 0;
            
            lotSize = CalculatePositionSize(sl, SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), false);
            
            if(!trade.Sell(lotSize, CurrentSymbol, 0, sl, tp, "Sell Order"))
            {
                Print("OpenSellOrder - Échec de l'ordre. Erreur: " + IntegerToString(GetLastError()), true);
            }
            else
            {
                lastSellPrice = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
                Print("OpenSellOrder - Nouveau prix de vente: " + DoubleToString(lastSellPrice, _Digits), true);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close All Buy Positions                                            |
//+------------------------------------------------------------------+
void CloseAllBuyPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == CurrentSymbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                trade.PositionClose(PositionGetTicket(i));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Close All Sell Positions                                           |
//+------------------------------------------------------------------+
void CloseAllSellPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == CurrentSymbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                trade.PositionClose(PositionGetTicket(i));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Count Positions                                                    |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE positionType)
{
    int count = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetInteger(POSITION_MAGIC) == Magic && 
               PositionGetString(POSITION_SYMBOL) == CurrentSymbol &&
               PositionGetInteger(POSITION_TYPE) == positionType)
            {
                count++;
            }
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Count Positions in Current Bar                                     |
//+------------------------------------------------------------------+
int CountPositionsInCurrentBar(ENUM_POSITION_TYPE positionType)
{
    int count = 0;
    datetime currentBarTime = iTime(CurrentSymbol, PERIOD_CURRENT, 0);
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetInteger(POSITION_MAGIC) == Magic && 
               PositionGetString(POSITION_SYMBOL) == CurrentSymbol &&
               PositionGetInteger(POSITION_TYPE) == positionType)
            {
                datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
                if(openTime >= currentBarTime)
                {
                    count++;
                }
            }
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Calculate Position Size                                            |
//+------------------------------------------------------------------+
double CalculatePositionSize(double stopLoss, double entryPrice, bool isBuy)
{
    if(LotType == LOT_TYPE_FIXED)
        return LotSize;
        
    if(LotType == LOT_TYPE_CURRENCY)
    {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double lotMultiplier = MathFloor(accountBalance / CurrencyAmount);
        double calculatedLot = BaseLot * lotMultiplier;
        
        // Normaliser le lot selon les limites du broker
        double minLot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(CurrentSymbol, SYMBOL_VOLUME_STEP);
        
        calculatedLot = MathMax(minLot, MathMin(maxLot, calculatedLot));
        calculatedLot = NormalizeDouble(calculatedLot / lotStep, 0) * lotStep;
        
        return calculatedLot;
    }
    
    return LotSize; // Fallback to fixed lot size
}

//+------------------------------------------------------------------+
//| Handle Trailing Stop Loss (Scalper style)                         |
//+------------------------------------------------------------------+
void HandleTrailingStopsScalper()
{
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
             PositionGetString(POSITION_SYMBOL) == CurrentSymbol) {
              
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
   
    // Récupération des valeurs Supertrend
    double st[];
    ArrayResize(st, 3);
    ArraySetAsSeries(st, true);
    if(CopyBuffer(stHandle, 0, 0, 3, st) <= 0) {
        Print("Error copying Supertrend buffer in HandleTrailingStopsScalper");
        return;
    }
   
    // Récupération des prix actuels
    double currentBid = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);
    double currentClose = SymbolInfoDouble(CurrentSymbol, SYMBOL_LAST);
   
    // Vérification de la tendance Supertrend
    bool isBullishTrend = currentClose > st[1];
    bool isBearishTrend = currentClose < st[1];
   
    // Gestion des positions Buy
    if(buyPositionCount > 0) {
        // Vérification du trailing stop
        if(Tral > 0 && TralStart > 0) {
            double buyTrailingStop = buyAveragePrice + TralStart * _Point;
            if(currentBid > buyTrailingStop) {
                double newSL = currentBid - Tral * _Point;
                for(int i = PositionsTotal() - 1; i >= 0; i--) {
                    if(PositionSelectByTicket(PositionGetTicket(i))) {
                        if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                           PositionGetString(POSITION_SYMBOL) == CurrentSymbol &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                            double currentSL = PositionGetDouble(POSITION_SL);
                            if(newSL > currentSL || currentSL == 0) {
                                trade.PositionModify(PositionGetTicket(i), newSL, 0);
                            }
                        }
                    }
                }
            }
        }
       
        // Vérification du take profit
        if(TakeProfit > 0) {
            double buyTakeProfit = buyAveragePrice + TakeProfit * _Point;
            if(currentBid >= buyTakeProfit) {
                for(int i = PositionsTotal() - 1; i >= 0; i--) {
                    if(PositionSelectByTicket(PositionGetTicket(i))) {
                        if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                           PositionGetString(POSITION_SYMBOL) == CurrentSymbol &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                            trade.PositionClose(PositionGetTicket(i));
                        }
                    }
                }
            }
        }
    }
   
    // Gestion des positions Sell
    if(sellPositionCount > 0) {
        // Vérification du trailing stop
        if(Tral > 0 && TralStart > 0) {
            double sellTrailingStop = sellAveragePrice - TralStart * _Point;
            if(currentAsk < sellTrailingStop) {
                double newSL = currentAsk + Tral * _Point;
                for(int i = PositionsTotal() - 1; i >= 0; i--) {
                    if(PositionSelectByTicket(PositionGetTicket(i))) {
                        if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                           PositionGetString(POSITION_SYMBOL) == CurrentSymbol &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                            double currentSL = PositionGetDouble(POSITION_SL);
                            if(newSL < currentSL || currentSL == 0) {
                                trade.PositionModify(PositionGetTicket(i), newSL, 0);
                            }
                        }
                    }
                }
            }
        }
       
        // Vérification du take profit
        if(TakeProfit > 0) {
            double sellTakeProfit = sellAveragePrice - TakeProfit * _Point;
            if(currentAsk <= sellTakeProfit) {
                for(int i = PositionsTotal() - 1; i >= 0; i--) {
                    if(PositionSelectByTicket(PositionGetTicket(i))) {
                        if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                           PositionGetString(POSITION_SYMBOL) == CurrentSymbol &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                            trade.PositionClose(PositionGetTicket(i));
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                      |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    datetime currentTime = TimeCurrent();
    MqlDateTime time;
    TimeToStruct(currentTime, time);
    
    // Convertir l'heure actuelle en minutes depuis minuit
    int currentTimeInMinutes = time.hour * 60 + time.min;
    int startTimeInMinutes = TimeStartHour * 60 + TimeStartMinute;
    int endTimeInMinutes = TimeEndHour * 60 + TimeEndMinute;
    
    bool isWithinHours;
    
    // Si la période de trading passe minuit
    if(endTimeInMinutes < startTimeInMinutes)
    {
        isWithinHours = (currentTimeInMinutes >= startTimeInMinutes || currentTimeInMinutes <= endTimeInMinutes);
        Print("=== VÉRIFICATION HEURES DE TRADING ===\n",
              "Heure actuelle: ", time.hour, ":", time.min, "\n",
              "Période de trading: ", TimeStartHour, ":", TimeStartMinute, " - ", TimeEndHour, ":", TimeEndMinute, "\n",
              "Statut: ", isWithinHours ? "DANS LES HEURES" : "HORS DES HEURES", "\n",
              "Période passe minuit: OUI", "\n",
              "Minutes actuelles: ", currentTimeInMinutes, "\n",
              "Minutes de début: ", startTimeInMinutes, "\n",
              "Minutes de fin: ", endTimeInMinutes);
    }
    // Si la période de trading est dans la même journée
    else
    {
        isWithinHours = (currentTimeInMinutes >= startTimeInMinutes && currentTimeInMinutes <= endTimeInMinutes);
        Print("=== VÉRIFICATION HEURES DE TRADING ===\n",
              "Heure actuelle: ", time.hour, ":", time.min, "\n",
              "Période de trading: ", TimeStartHour, ":", TimeStartMinute, " - ", TimeEndHour, ":", TimeEndMinute, "\n",
              "Statut: ", isWithinHours ? "DANS LES HEURES" : "HORS DES HEURES", "\n",
              "Période passe minuit: NON", "\n",
              "Minutes actuelles: ", currentTimeInMinutes, "\n",
              "Minutes de début: ", startTimeInMinutes, "\n",
              "Minutes de fin: ", endTimeInMinutes);
    }
    
    if(!isWithinHours)
    {
        Print("TRADING BLOQUÉ - Hors des heures de trading");
    }
    
    return isWithinHours;
}

//+------------------------------------------------------------------+
//| Log Management                                                     |
//+------------------------------------------------------------------+
void LogMessage(string message, bool forceLog = false)
{
    datetime currentTime = TimeCurrent();
    string log = TimeToString(currentTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS) + " | " + message;
    
    // Force print to MetaTrader journal
    Print(log);
    
    // Write to file
    int handle = FileOpen("ScalperSTZZ_Log.txt", FILE_WRITE|FILE_READ|FILE_TXT|FILE_COMMON);
    if(handle != INVALID_HANDLE)
    {
        FileSeek(handle, 0, SEEK_END);
        FileWrite(handle, log);
        FileClose(handle);
    }
}

//+------------------------------------------------------------------+
//| Check if trade is allowed based on limits                         |
//+------------------------------------------------------------------+
bool IsTradeAllowed(bool isBuy)
{
    if(MaxTrades > 0)
    {
        int totalTrades = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionGetSymbol(i) == CurrentSymbol && PositionGetInteger(POSITION_MAGIC) == Magic)
                totalTrades++;
        }
        if(totalTrades >= MaxTrades)
            return false;
    }
    
    if(isBuy && MaxBuyTrades > 0)
    {
        int buyTrades = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionGetSymbol(i) == CurrentSymbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                buyTrades++;
        }
        if(buyTrades >= MaxBuyTrades)
            return false;
    }
    else if(!isBuy && MaxSellTrades > 0)
    {
        int sellTrades = 0;
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionGetSymbol(i) == CurrentSymbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                sellTrades++;
        }
        if(sellTrades >= MaxSellTrades)
            return false;
    }
    
    if(MaxDailyTrades > 0)
    {
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        int dailyTrades = 0;
        HistorySelect(today, TimeCurrent());
        for(int i = 0; i < HistoryDealsTotal(); i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic)
                dailyTrades++;
        }
        if(dailyTrades >= MaxDailyTrades)
            return false;
    }
    
    if(isBuy && MaxDailyBuyTrades > 0)
    {
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        int dailyBuyTrades = 0;
        HistorySelect(today, TimeCurrent());
        for(int i = 0; i < HistoryDealsTotal(); i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic &&
               HistoryDealGetString(ticket, DEAL_SYMBOL) == CurrentSymbol &&
               HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_BUY)
                dailyBuyTrades++;
        }
        if(dailyBuyTrades >= MaxDailyBuyTrades)
            return false;
    }
    else if(!isBuy && MaxDailySellTrades > 0)
    {
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        int dailySellTrades = 0;
        HistorySelect(today, TimeCurrent());
        for(int i = 0; i < HistoryDealsTotal(); i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic &&
               HistoryDealGetString(ticket, DEAL_SYMBOL) == CurrentSymbol &&
               HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_SELL)
                dailySellTrades++;
        }
        if(dailySellTrades >= MaxDailySellTrades)
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if daily target or loss has been reached                     |
//+------------------------------------------------------------------+
bool IsDailyTargetReached()
{
    if(DailyTargetCurrency <= 0.0 && DailyTargetPercent <= 0.0 && 
       DailyLossCurrency <= 0.0 && DailyLossPercent <= 0.0)
    {
        return false;
    }
    
    // Vérifier si on doit recalculer (toutes les 30 secondes ou si changement dans les positions/deals)
    datetime currentTime = TimeCurrent();
    int currentDealsCount = HistoryDealsTotal();
    int currentPositionsCount = PositionsTotal();
    
    bool shouldRecalculate = false;
    if(currentTime - lastCalculationTime >= 30)  // Recalcul toutes les 30 secondes
    {
        shouldRecalculate = true;
    }
    else if(currentDealsCount != lastDealsCount || currentPositionsCount != lastPositionsCount)
    {
        shouldRecalculate = true;
    }
    
    if(!shouldRecalculate)
    {
        return (DailyTargetCurrency > 0.0 && lastCalculatedProfit >= DailyTargetCurrency) ||
               (DailyTargetPercent > 0.0 && lastCalculatedProfit >= AccountInfoDouble(ACCOUNT_BALANCE) * DailyTargetPercent / 100.0) ||
               (DailyLossCurrency > 0.0 && lastCalculatedProfit <= -DailyLossCurrency) ||
               (DailyLossPercent > 0.0 && lastCalculatedProfit <= -AccountInfoDouble(ACCOUNT_BALANCE) * DailyLossPercent / 100.0);
    }
    
    // Mise à jour des compteurs
    lastCalculationTime = currentTime;
    lastDealsCount = currentDealsCount;
    lastPositionsCount = currentPositionsCount;
    
    datetime today = StringToTime(TimeToString(currentTime, TIME_DATE));
    double dailyProfit = 0.0;
    
    // Calcul du profit des trades fermés
    if(HistorySelect(today, currentTime))
    {
        for(int i = 0; i < currentDealsCount; i++)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic &&
               HistoryDealGetString(ticket, DEAL_SYMBOL) == CurrentSymbol)
            {
                dailyProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            }
        }
    }
    
    // Calcul du profit des positions ouvertes
    for(int i = 0; i < currentPositionsCount; i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == CurrentSymbol && 
               PositionGetInteger(POSITION_MAGIC) == Magic)
            {
                dailyProfit += PositionGetDouble(POSITION_PROFIT);
            }
        }
    }
    
    // Mise à jour du cache
    lastCalculatedProfit = dailyProfit;
    
    // Vérification des cibles et des pertes
    if(DailyTargetCurrency > 0.0 && dailyProfit >= DailyTargetCurrency)
    {
        return true;
    }
    
    if(DailyTargetPercent > 0.0)
    {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double targetAmount = accountBalance * DailyTargetPercent / 100.0;
        if(dailyProfit >= targetAmount)
        {
            return true;
        }
    }
    
    if(DailyLossCurrency > 0.0 && dailyProfit <= -DailyLossCurrency)
    {
        return true;
    }
    
    if(DailyLossPercent > 0.0)
    {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double lossAmount = accountBalance * DailyLossPercent / 100.0;
        if(dailyProfit <= -lossAmount)
        {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Manage existing positions                                          |
//+------------------------------------------------------------------+
void ManagePositions()
{
    // Vérifier le changement de direction de la Supertrend si le mode le permet
    if(SupertrendMode == SUPERTREND_FILTER_AND_CLOSE)
    {
        double st[];
        ArrayResize(st, 3);
        ArraySetAsSeries(st, true);
        
        // Copier les valeurs de la Supertrend
        if(CopyBuffer(stHandle, 0, 0, 3, st) > 0)
        {
            double close1 = iClose(CurrentSymbol, Timeframe, 1);
            
            // Vérifier la tendance actuelle
            bool isSupertrendBullish = close1 > st[1];
            bool isSupertrendBearish = close1 < st[1];
            
            // Si la tendance est baissière, fermer toutes les positions d'achat
            if(isSupertrendBearish)
            {
                for(int i = PositionsTotal() - 1; i >= 0; i--)
                {
                    if(PositionSelectByTicket(PositionGetTicket(i)))
                    {
                        if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                           PositionGetString(POSITION_SYMBOL) == CurrentSymbol &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                        {
                            trade.PositionClose(PositionGetTicket(i));
                            Print("Position d'achat fermée suite au changement de tendance Supertrend", true);
                        }
                    }
                }
                // Réinitialiser le dernier prix d'achat pour permettre de nouveaux achats
                lastBuyPrice = 0;
            }
            // Si la tendance est haussière, fermer toutes les positions de vente
            else if(isSupertrendBullish)
            {
                for(int i = PositionsTotal() - 1; i >= 0; i--)
                {
                    if(PositionSelectByTicket(PositionGetTicket(i)))
                    {
                        if(PositionGetInteger(POSITION_MAGIC) == Magic && 
                           PositionGetString(POSITION_SYMBOL) == CurrentSymbol &&
                           PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                        {
                            trade.PositionClose(PositionGetTicket(i));
                            Print("Position de vente fermée suite au changement de tendance Supertrend", true);
                        }
                    }
                }
                // Réinitialiser le dernier prix de vente pour permettre de nouvelles ventes
                lastSellPrice = 0;
            }
        }
    }
    
    // Gérer les trailing stops
    HandleTrailingStopsScalper();
}

//+------------------------------------------------------------------+
//| Open new position                                                  |
//+------------------------------------------------------------------+
void OpenPosition(bool isBuy)
{
    if(isBuy)
        OpenBuyOrder();
    else
        OpenSellOrder();
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    // Vérifier si le spread est acceptable
    double currentSpread = SymbolInfoInteger(CurrentSymbol, SYMBOL_SPREAD) * Point();
    if(currentSpread > MaxSpread)
    {
        Print("SPREAD TROP ÉLEVÉ: ", currentSpread, " > ", MaxSpread);
        return;
    }
    
    // Vérifier si l'objectif quotidien est atteint
    if(IsDailyTargetReached())
    {
        Print("OBJECTIF QUOTIDIEN ATTEINT - Fermeture des positions");
        CloseAllBuyPositions();
        CloseAllSellPositions();
        return;
    }
    
    // Gérer les trailing stops et les positions existantes
    HandleTrailingStopsScalper();
    ManagePositions();
    
    // Vérifier si on est dans les heures de trading uniquement pour les nouvelles entrées
    if(!IsWithinTradingHours())
    {
        return; // Sortir après avoir géré les positions existantes
    }
    
    // Le reste du code pour les nouvelles entrées
    int bars = iBars(CurrentSymbol, Timeframe);
    if(totalBars != bars)
    {
        totalBars = bars;
        
        double st[];
        ArrayResize(st, 3);
        ArraySetAsSeries(st, true);
        
        // Copy Supertrend buffer with retry
        int maxRetries = 5;
        int retryDelay = 100; // milliseconds
        int copied = 0;
        
        for(int retry = 0; retry < maxRetries; retry++)
        {
            copied = CopyBuffer(stHandle, 0, 0, 3, st);
            if(copied > 0) break;
            Sleep(retryDelay);
        }
        
        if(copied <= 0)
        {
            Print("Error copying Supertrend buffer. Error code: " + IntegerToString(GetLastError()));
            return;
        }
        
        double close1 = iClose(CurrentSymbol, Timeframe, 1);
        double close2 = iClose(CurrentSymbol, Timeframe, 2);
        
        if(close1 == 0 || close2 == 0)
        {
            Print("Error getting close prices");
            return;
        }
        
        // Vérifier la tendance Supertrend
        bool isSupertrendBullish = close1 > st[1];
        bool isSupertrendBearish = close1 < st[1];
        
        // Vérifier les conditions d'entrée une seule fois
        bool canTrade = CheckScalperEntryConditions(st, close1);
        
        // Ouvrir de nouvelles positions si les conditions sont remplies
        if(canTrade && IsTradeAllowed(true))
        {
            if(SupertrendMode == SUPERTREND_DISABLED || 
               (SupertrendMode != SUPERTREND_DISABLED && isSupertrendBullish))
            {
                OpenPosition(true);
            }
            else if(SupertrendMode == SUPERTREND_DISABLED || 
                    (SupertrendMode != SUPERTREND_DISABLED && isSupertrendBearish))
            {
                OpenPosition(false);
            }
        }
    }
} 
