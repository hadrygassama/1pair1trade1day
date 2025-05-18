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

enum ENUM_SUPERTREND_MODE
{
    SUPERTREND_FILTER_AND_CLOSE = 1,   // Supertrend Filter & Close on change (active only if UseSupertrend is true)
    SUPERTREND_FILTER_ONLY = 2         // Supertrend Filter Only (active only if UseSupertrend is true)
};

enum ENUM_MA_MODE
{
    MA_FILTER_AND_CLOSE = 1,   // MA Filter & Close on change (active only if UseMA200 is true)
    MA_FILTER_ONLY = 2         // MA Filter Only (active only if UseMA200 is true)
};

enum ENUM_RSI_MODE
{
    RSI_FILTER_AND_CLOSE = 1,   // RSI Filter & Close on change (active only if UseRSI is true)
    RSI_FILTER_ONLY = 2         // RSI Filter Only (active only if UseRSI is true)
};

enum ENUM_RSI_LOGIC {
    RSI_CONTINUATION = 1,  // Continuation
    RSI_REVERSAL = 2       // Reversal
};

enum ENUM_PRICE_CONDITION {
    PRICE_CONDITION_BOTH = 0,         // Trade above and below
    PRICE_CONDITION_ABOVE_BELOW = 1   // Trade only above buy and Trade only below sell
};

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
// === Expert Settings ===
input group "=== Expert Settings ==="
input int      Magic = 548762;         // Magic Number
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;  // Timeframe

// === Trading Direction and Mode ===
input group "=== Trading Direction and Mode ==="
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Trade Direction
input ENUM_PRICE_CONDITION PriceCondition = PRICE_CONDITION_BOTH;  // Price condition for entries

// === Supertrend Settings ===
input group "=== Supertrend Settings ==="
input bool    UseSupertrend = true;     // Utiliser le filtre Supertrend
input ENUM_SUPERTREND_MODE SupertrendMode = SUPERTREND_FILTER_ONLY;  // Supertrend Mode
input int    ATR_Period = 3;        // ATR Period
input double ATR_Multiplier = 16.0;   // ATR Multiplier

// === MA 200 Filter Settings ===
input group "=== MA 200 Filter Settings ==="
input bool    UseMA200 = true;          // Utiliser le filtre MA 200
input ENUM_MA_MODE MAMode = MA_FILTER_ONLY;  // MA Mode
input int MAPeriod = 200;                    // Période de la MA

// === RSI Filter Settings ===
input group "=== RSI Filter Settings ==="
input bool    UseRSI = true;          // Utiliser le filtre RSI
input ENUM_RSI_MODE RSIMode = RSI_FILTER_ONLY;  // RSI Mode
input ENUM_RSI_LOGIC RSILogic = RSI_CONTINUATION;  // RSI Logic
input int RSIPeriod = 14;             // Période du RSI
input int RSIOverbought = 70;         // Niveau de surachat
input int RSIOversold = 30;           // Niveau de survente

// === Position Size Settings ===
input group "=== Position Size Settings ==="
input ENUM_LOT_TYPE LotType = LOT_TYPE_CURRENCY;  // Lot size type
input double LotSize = 0.1;          // Fixed lot size
input double CurrencyAmount = 10000;  // Amount per lot (in account currency)
input double BaseLot = 0.01;         // Base lot size for currency amount
input double RiskPercent = 1;      // Risk percentage per trade

// === Order Management ===
input group "=== Order Management ==="
input int      FixedTP = 0;       // Take Profit (points, 0=disabled)
input int      FixedSL = 0;          // Stop Loss (points, 0=disabled)
input int      OpenTime = 600;          // Time between orders (seconds)

// === Trailing Stop Settings ===
input group "=== Trailing Stop Settings ==="
input int      TrailingStopPips = 25;             // Trailing stop distance (in pips, 0=disabled)
input int      TrailingStartPips = 10;        // Distance to start trailing (in pips, 0=disabled)
input double   TakeProfit = 45;       // Take Profit (in pips, 0=disabled)

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

// === Trading Hours ===
input group "=== Trading Hours ==="
input int      TimeStartHour = 0;      // Start hour
input int      TimeStartMinute = 0;    // Start minute
input int      TimeEndHour = 23;       // End hour
input int      TimeEndMinute = 59;     // End minute
input bool     AutoDetectBrokerOffset = true;  // Auto-detect GMT offset
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
int maHandle;                         // MA 200 indicator handle
int rsiHandle;                        // RSI indicator handle
int totalBars;                        // Total number of bars
double lotSize;                       // Lot size

// Scalper variables
datetime lastOpenTime = 0;
double lastBidPrice = 0;
double lastBuyPrice = 0;    // Last buy price
double lastSellPrice = 0;   // Last sell price

// Trading limits variables
datetime lastCalculationTime = 0;
int lastDealsCount = 0;
int lastPositionsCount = 0;
double lastCalculatedProfit = 0.0;

// RSI state tracking
enum ENUM_RSI_STATE {
    RSI_BEARISH = 0,  // RSI < RSIOversold
    RSI_BULLISH = 1   // RSI > RSIOverbought
};
ENUM_RSI_STATE lastRSIState = RSI_BEARISH;  // État initial bearish
ENUM_RSI_STATE previousRSIState = RSI_BEARISH;  // Dernier état connu

struct TradingConditions {
    bool canBuy;
    bool canSell;
};

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
    
    // Check if indicator is initialized successfully
    if(stHandle == INVALID_HANDLE)
    {
        Print("Error initializing Supertrend indicator. Error code: " + IntegerToString(GetLastError()));
        return(INIT_FAILED);
    }
    
    // Initialize MA 200
    maHandle = iMA(CurrentSymbol, Timeframe, MAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    
    // Check if MA 200 is initialized successfully
    if(maHandle == INVALID_HANDLE)
    {
        Print("Error initializing MA 200 indicator. Error code: " + IntegerToString(GetLastError()));
        return(INIT_FAILED);
    }
    
    // Initialize RSI
    rsiHandle = iRSI(CurrentSymbol, Timeframe, RSIPeriod, PRICE_CLOSE);
    
    // Check if RSI is initialized successfully
    if(rsiHandle == INVALID_HANDLE)
    {
        Print("Error initializing RSI indicator. Error code: " + IntegerToString(GetLastError()));
        return(INIT_FAILED);
    }
    
    totalBars = iBars(CurrentSymbol, Timeframe);
    lotSize = LotSize;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(stHandle != INVALID_HANDLE)
        IndicatorRelease(stHandle);
    if(maHandle != INVALID_HANDLE)
        IndicatorRelease(maHandle);
    if(rsiHandle != INVALID_HANDLE)
        IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    // Vérifier si on est dans les heures de trading AVANT toute opération
    if(!IsWithinTradingHours())
    {
        return; // Sortir immédiatement sans faire aucune opération
    }
    
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
    
    // Copier les valeurs des indicateurs
    double st[], ma[], close[], rsi[];
    ArrayResize(st, 3);
    ArrayResize(ma, 3);
    ArrayResize(close, 3);
    ArrayResize(rsi, 3);
    ArraySetAsSeries(st, true);
    ArraySetAsSeries(ma, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(rsi, true);
    
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
    
    // Copy MA 200 buffer
    if(CopyBuffer(maHandle, 0, 0, 3, ma) <= 0)
    {
        Print("Error copying MA 200 buffer. Error code: " + IntegerToString(GetLastError()));
        return;
    }
    
    // Copier les prix de clôture
    if(CopyClose(CurrentSymbol, Timeframe, 0, 3, close) <= 0)
    {
        Print("Error copying close prices");
        return;
    }
    
    // Copier les valeurs du RSI
    if(CopyBuffer(rsiHandle, 0, 0, 3, rsi) <= 0)
    {
        Print("Error copying RSI buffer");
        return;
    }
    
    // Vérifier les conditions d'entrée
    TradingConditions conditions = CheckScalperEntryConditions(st, ma, close);
    
    // Ouvrir de nouvelles positions si les conditions sont remplies
    if(IsTradeAllowed(true))
    {
        if(conditions.canBuy)
        {
            OpenPosition(true);
        }
        else if(conditions.canSell)
        {
            OpenPosition(false);
        }
    }
}

//+------------------------------------------------------------------+
//| Check Scalper Entry Conditions                                     |
//+------------------------------------------------------------------+
TradingConditions CheckScalperEntryConditions(double &st[], double &ma[], double &close[])
{
    TradingConditions conditions;
    conditions.canBuy = false;
    conditions.canSell = false;
    
    // Sauvegarder l'état précédent avant de le modifier
    previousRSIState = lastRSIState;
    
    // Vérifier les conditions de la Supertrend
    bool stBullish = close[1] > st[1];
    bool stBearish = close[1] < st[1];
    
    // Vérifier les conditions de la MA 200
    bool maBullish = close[1] > ma[1];  // Prix au-dessus de la MA200
    bool maBearish = close[1] < ma[1];  // Prix en-dessous de la MA200
    
    // Vérifier les conditions du RSI
    double rsi[];
    ArrayResize(rsi, 3);
    ArraySetAsSeries(rsi, true);
    
    if(CopyBuffer(rsiHandle, 0, 0, 3, rsi) <= 0)
    {
        Print("Error copying RSI buffer");
        return conditions;
    }
    
    // Définir l'état RSI en fonction des niveaux et de la logique choisie
    if(RSILogic == RSI_CONTINUATION)
    {
        if(rsi[1] > RSIOverbought) {
            lastRSIState = RSI_BULLISH;   // RSI > RSIOverbought = bullish
        }
        else if(rsi[1] < RSIOversold) {
            lastRSIState = RSI_BEARISH;   // RSI < RSIOversold = bearish
        }
        else {
            // Si dans la zone neutre, on garde le dernier état connu
            lastRSIState = previousRSIState;
        }
    }
    else // RSI_REVERSAL
    {
        if(rsi[1] > RSIOverbought) {
            lastRSIState = RSI_BEARISH;   // RSI > RSIOverbought = bearish
        }
        else if(rsi[1] < RSIOversold) {
            lastRSIState = RSI_BULLISH;   // RSI < RSIOversold = bullish
        }
        else {
            // Si dans la zone neutre, on garde le dernier état connu
            lastRSIState = previousRSIState;
        }
    }
    
    // Log des valeurs RSI et des états
    string rsiStateStr = lastRSIState == RSI_BULLISH ? "Bullish" : "Bearish";
    Print("DEBUG RSI - Values: ", rsi[1], 
          " | RSI State: ", rsiStateStr,
          " | Previous State: ", (previousRSIState == RSI_BULLISH ? "Bullish" : "Bearish"));
    
    // Si seul le RSI est activé
    if(UseRSI && !UseSupertrend && !UseMA200)
    {
        conditions.canBuy = (lastRSIState == RSI_BULLISH);
        conditions.canSell = (lastRSIState == RSI_BEARISH);
    }
    // Si tous les filtres sont activés
    else if(UseSupertrend && UseMA200 && UseRSI)
    {
        conditions.canBuy = stBullish && maBullish && (lastRSIState == RSI_BULLISH);
        conditions.canSell = stBearish && maBearish && (lastRSIState == RSI_BEARISH);
    }
    // Si Supertrend et MA sont activés
    else if(UseSupertrend && UseMA200)
    {
        conditions.canBuy = stBullish && maBullish;
        conditions.canSell = stBearish && maBearish;
    }
    // Si Supertrend et RSI sont activés
    else if(UseSupertrend && UseRSI)
    {
        conditions.canBuy = stBullish && (lastRSIState == RSI_BULLISH);
        conditions.canSell = stBearish && (lastRSIState == RSI_BEARISH);
    }
    // Si MA et RSI sont activés
    else if(UseMA200 && UseRSI)
    {
        conditions.canBuy = maBullish && (lastRSIState == RSI_BULLISH);
        conditions.canSell = maBearish && (lastRSIState == RSI_BEARISH);
    }
    // Si seul le Supertrend est activé
    else if(UseSupertrend)
    {
        conditions.canBuy = stBullish;
        conditions.canSell = stBearish;
    }
    // Si seule la MA 200 est activée
    else if(UseMA200)
    {
        conditions.canBuy = maBullish;
        conditions.canSell = maBearish;
    }
    // Si aucun filtre n'est activé
    else
    {
        conditions.canBuy = true;
        conditions.canSell = true;
    }
    
    return conditions;
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
    if(TradeDirection == TRADE_SELL_ONLY) {
        LogMessage("OpenBuyOrder - Trading direction ne permet pas les achats", true);
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
                LogMessage("OpenBuyOrder - Échec de l'ordre. Erreur: " + IntegerToString(GetLastError()), true);
            }
            else
            {
                lastBuyPrice = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);
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
        LogMessage("OpenSellOrder - Trading direction ne permet pas les ventes", true);
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
                LogMessage("OpenSellOrder - Échec de l'ordre. Erreur: " + IntegerToString(GetLastError()), true);
            }
            else
            {
                lastSellPrice = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
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
    // Réinitialiser les prix de référence après avoir fermé toutes les positions d'achat
    lastBuyPrice = 0;
    lastSellPrice = 0;
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
    // Réinitialiser les prix de référence après avoir fermé toutes les positions de vente
    lastBuyPrice = 0;
    lastSellPrice = 0;
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
   
    // Récupération des prix actuels
    double currentBid = SymbolInfoDouble(CurrentSymbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK);
   
    // Gestion des positions Buy
    if(buyPositionCount > 0) {
        // Vérification du trailing stop
        if(TrailingStopPips > 0 && TrailingStartPips > 0) {
            double buyTrailingStop = buyAveragePrice + TrailingStartPips * _Point;
            if(currentBid > buyTrailingStop) {
                double newSL = currentBid - TrailingStopPips * _Point;
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
                // Réinitialiser les prix de référence après avoir atteint le profit
                lastBuyPrice = 0;
                lastSellPrice = 0;
            }
        }
    }
   
    // Gestion des positions Sell
    if(sellPositionCount > 0) {
        // Vérification du trailing stop
        if(TrailingStopPips > 0 && TrailingStartPips > 0) {
            double sellTrailingStop = sellAveragePrice - TrailingStartPips * _Point;
            if(currentAsk < sellTrailingStop) {
                double newSL = currentAsk + TrailingStopPips * _Point;
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
                // Réinitialiser les prix de référence après avoir atteint le profit
                lastBuyPrice = 0;
                lastSellPrice = 0;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get Broker GMT Offset                                              |
//+------------------------------------------------------------------+
int GetBrokerGMTOffset()
{
    datetime serverTime = TimeCurrent();
    datetime localTime = TimeLocal();
    int offset = (int)((serverTime - localTime) / 3600);
    return BrokerIsAheadOfGMT ? offset : -offset;
}

//+------------------------------------------------------------------+
//| Adjust Time For Broker                                             |
//+------------------------------------------------------------------+
datetime AdjustTimeForBroker(datetime time)
{
    int offset = AutoDetectBrokerOffset ? GetBrokerGMTOffset() : ManualBrokerOffset;
    return time + offset * 3600;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                      |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    datetime currentTime = TimeCurrent();  // Server time
    currentTime = AdjustTimeForBroker(currentTime);  // Adjust for broker offset
    
    MqlDateTime time;
    TimeToStruct(currentTime, time);
    
    int currentHour = time.hour;
    int currentMinute = time.min;
    
    // Convert current time to minutes since midnight
    int currentTimeInMinutes = currentHour * 60 + currentMinute;
    int startTimeInMinutes = TimeStartHour * 60 + TimeStartMinute;
    int endTimeInMinutes = TimeEndHour * 60 + TimeEndMinute;
    
    bool isWithinHours;
    
    // If trading period crosses midnight
    if(endTimeInMinutes < startTimeInMinutes)
    {
        isWithinHours = (currentTimeInMinutes >= startTimeInMinutes || currentTimeInMinutes <= endTimeInMinutes);
    }
    // If trading period is within the same day
    else
    {
        isWithinHours = (currentTimeInMinutes >= startTimeInMinutes && currentTimeInMinutes <= endTimeInMinutes);
    }
    
    return isWithinHours;
}

//+------------------------------------------------------------------+
//| Log Management                                                     |
//+------------------------------------------------------------------+
void LogMessage(string message, bool forceLog = false)
{
    if(!forceLog) return; // Only log errors
    
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
    if(UseSupertrend && SupertrendMode == SUPERTREND_FILTER_AND_CLOSE)
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
                // Réinitialiser les deux prix de référence après fermeture des positions d'achat
                lastBuyPrice = 0;
                lastSellPrice = 0;
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
                // Réinitialiser les deux prix de référence après fermeture des positions de vente
                lastBuyPrice = 0;
                lastSellPrice = 0;
            }
        }
    }

    // Vérifier le changement de direction de la MA si le mode le permet
    if(UseMA200 && MAMode == MA_FILTER_AND_CLOSE)
    {
        double ma[];
        ArrayResize(ma, 3);
        ArraySetAsSeries(ma, true);
        
        // Copier les valeurs de la MA
        if(CopyBuffer(maHandle, 0, 0, 3, ma) > 0)
        {
            double close1 = iClose(CurrentSymbol, Timeframe, 1);
            
            // Vérifier la tendance actuelle
            bool isMABullish = close1 > ma[1];
            bool isMABearish = close1 < ma[1];
            
            // Si la tendance est baissière, fermer toutes les positions d'achat
            if(isMABearish)
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
                            Print("Position d'achat fermée suite au changement de tendance MA", true);
                        }
                    }
                }
                // Réinitialiser les deux prix de référence après fermeture des positions d'achat
                lastBuyPrice = 0;
                lastSellPrice = 0;
            }
            // Si la tendance est haussière, fermer toutes les positions de vente
            else if(isMABullish)
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
                            Print("Position de vente fermée suite au changement de tendance MA", true);
                        }
                    }
                }
                // Réinitialiser les deux prix de référence après fermeture des positions de vente
                lastBuyPrice = 0;
                lastSellPrice = 0;
            }
        }
    }

    // Vérifier le changement de direction du RSI si le mode le permet
    if(UseRSI && RSIMode == RSI_FILTER_AND_CLOSE)
    {
        double rsi[];
        ArrayResize(rsi, 2);
        ArraySetAsSeries(rsi, true);
        
        if(CopyBuffer(rsiHandle, 0, 0, 2, rsi) > 0)
        {
            bool isInBuyZone = rsi[1] >= RSIOversold;    // RSI actuel au-dessus de 50
            bool isInSellZone = rsi[1] <= RSIOverbought; // RSI actuel en-dessous de 50
            
            // Fermer les positions BUY si RSI passe en-dessous de 50
            if(!isInBuyZone)
            {
                CloseAllBuyPositions();
                lastBuyPrice = 0;
                lastSellPrice = 0;
                Print("Fermeture des positions BUY - RSI passe en-dessous de ", RSIOversold, " (", rsi[1], ")");
            }
            
            // Fermer les positions SELL si RSI passe au-dessus de 50
            if(!isInSellZone)
            {
                CloseAllSellPositions();
                lastBuyPrice = 0;
                lastSellPrice = 0;
                Print("Fermeture des positions SELL - RSI passe au-dessus de ", RSIOverbought, " (", rsi[1], ")");
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

