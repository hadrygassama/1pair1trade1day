//+------------------------------------------------------------------+
//|                                           DoubleTopBottom.mq5 |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

// Input parameters
input int      LookbackPeriod = 20;    // Période de recherche des sommets/creux
input double   MinDistance = 0.0002;    // Distance minimale entre les sommets/creux
input double   LotSize = 0.1;           // Taille du lot
input int      StopLoss = 100;          // Stop Loss en points
input int      TakeProfit = 200;        // Take Profit en points
input bool     UseTrailingStop = true;  // Utiliser le trailing stop
input int      TrailingStop = 50;       // Trailing stop en points

// Variables globales
int handle;
double highBuffer[];
double lowBuffer[];
int patternFound = 0; // 0: aucun, 1: double sommet, 2: double creux

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialisation des buffers
    ArraySetAsSeries(highBuffer, true);
    ArraySetAsSeries(lowBuffer, true);
    ArrayResize(highBuffer, LookbackPeriod);
    ArrayResize(lowBuffer, LookbackPeriod);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ArrayFree(highBuffer);
    ArrayFree(lowBuffer);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Mise à jour des buffers
    for(int i = 0; i < LookbackPeriod; i++)
    {
        highBuffer[i] = iHigh(_Symbol, PERIOD_CURRENT, i);
        lowBuffer[i] = iLow(_Symbol, PERIOD_CURRENT, i);
    }
    
    // Vérification des positions ouvertes
    if(PositionsTotal() > 0)
    {
        if(UseTrailingStop)
            ManageTrailingStop();
        return;
    }
    
    // Recherche des patterns
    patternFound = FindPattern();
    
    // Exécution des ordres selon le pattern trouvé
    if(patternFound == 1) // Double sommet
    {
        OpenSellOrder();
    }
    else if(patternFound == 2) // Double creux
    {
        OpenBuyOrder();
    }
}

//+------------------------------------------------------------------+
//| Recherche des patterns de double sommet/creux                    |
//+------------------------------------------------------------------+
int FindPattern()
{
    // Recherche du double sommet
    for(int i = 2; i < LookbackPeriod-2; i++)
    {
        if(highBuffer[i] > highBuffer[i-1] && highBuffer[i] > highBuffer[i+1] &&
           highBuffer[i+2] > highBuffer[i+1] && highBuffer[i+2] > highBuffer[i+3] &&
           MathAbs(highBuffer[i] - highBuffer[i+2]) < MinDistance)
        {
            return 1; // Double sommet trouvé
        }
    }
    
    // Recherche du double creux
    for(int i = 2; i < LookbackPeriod-2; i++)
    {
        if(lowBuffer[i] < lowBuffer[i-1] && lowBuffer[i] < lowBuffer[i+1] &&
           lowBuffer[i+2] < lowBuffer[i+1] && lowBuffer[i+2] < lowBuffer[i+3] &&
           MathAbs(lowBuffer[i] - lowBuffer[i+2]) < MinDistance)
        {
            return 2; // Double creux trouvé
        }
    }
    
    return 0; // Aucun pattern trouvé
}

//+------------------------------------------------------------------+
//| Ouverture d'un ordre d'achat                                     |
//+------------------------------------------------------------------+
void OpenBuyOrder()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = ask - StopLoss * _Point;
    double tp = ask + TakeProfit * _Point;
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = ORDER_TYPE_BUY;
    request.price = ask;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = 123456;
    
    OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Ouverture d'un ordre de vente                                    |
//+------------------------------------------------------------------+
void OpenSellOrder()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = bid + StopLoss * _Point;
    double tp = bid - TakeProfit * _Point;
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = ORDER_TYPE_SELL;
    request.price = bid;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = 123456;
    
    OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Gestion du trailing stop                                         |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                double positionSL = PositionGetDouble(POSITION_SL);
                double positionTP = PositionGetDouble(POSITION_TP);
                double positionPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
                
                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                {
                    if(currentPrice - positionPrice > TrailingStop * _Point)
                    {
                        double newSL = currentPrice - TrailingStop * _Point;
                        if(newSL > positionSL)
                        {
                            MqlTradeRequest request = {};
                            MqlTradeResult result = {};
                            
                            request.action = TRADE_ACTION_SLTP;
                            request.symbol = _Symbol;
                            request.sl = newSL;
                            request.tp = positionTP;
                            request.position = PositionGetTicket(i);
                            
                            OrderSend(request, result);
                        }
                    }
                }
                else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                {
                    if(positionPrice - currentPrice > TrailingStop * _Point)
                    {
                        double newSL = currentPrice + TrailingStop * _Point;
                        if(newSL < positionSL || positionSL == 0)
                        {
                            MqlTradeRequest request = {};
                            MqlTradeResult result = {};
                            
                            request.action = TRADE_ACTION_SLTP;
                            request.symbol = _Symbol;
                            request.sl = newSL;
                            request.tp = positionTP;
                            request.position = PositionGetTicket(i);
                            
                            OrderSend(request, result);
                        }
                    }
                }
            }
        }
    }
} 