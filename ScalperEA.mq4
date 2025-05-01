#property copyright "Copyright 2024"
#property link      "https://www.example.com"
#property version   "1.00"
#property strict

// Error Codes
enum ErrorCodes {
    ERR_NO_ERROR = 0,
    ERR_TRADING_NOT_ALLOWED = 1,
    ERR_INVALID_DIGITS = 2,
    ERR_INIT_FAILED = 3
};

// External Parameters
input group "Trading Settings"
input double FixedLots = 0.01;              // Fixed Lot Size
input int TakeProfit = 30;                  // Take Profit in Points
input double Tral = 20;                     // Trailing Stop in Points
input double TralStart = 5;                 // Trailing Start in Points
input double PipsStep = 35;                 // Pips Step for Grid
input int OpenTime = 1;                     // Open Time in Minutes

input group "Money Management"
input string PercentageRiskSettings = "***************************";
input double PercentageRisk = 0.1;          // Risk Percentage
input int PercentageRiskBasedOnPointsMovement = 100; // Points for Risk Calculation
input string BalanceRatioSettings = "***************************";
input double ForEvery = 1000;               // Balance for Every
input double UseLotsForEveryBalance = 0.01; // Lots for Every Balance
input string LotsSelection = "***************************";
input LotAss LotAssignment = Fixed;         // Lot Assignment Method

input group "Time Settings"
input double TimeStart = 2;                 // Trading Start Hour
input double TimeEnd = 23;                  // Trading End Hour
input double MaxSpread = 40;                // Maximum Allowed Spread

input group "Risk Management"
input bool CloseTradesAtPercentageDrawdown; // Enable Percentage Drawdown Protection
input double PercentageDrawdown = 5;        // Maximum Drawdown Percentage
input bool CloseTradesAtFixedDrawdown;      // Enable Fixed Drawdown Protection
input double FixedDrawdown = 1000;          // Maximum Fixed Drawdown
input bool ResumeTradingAtNextDayAfterDrawdown; // Resume Trading Next Day

input group "EA Settings"
input int Magic = 2021;                     // Magic Number
input bool Info = true;                     // Show Info Panel
input color TextColor = White;              // Text Color
input color InfoDataColor = DodgerBlue;     // Info Data Color
input color FonColor = 0;                   // Background Color
input int FontSizeInfo = 7;                 // Font Size
input int SpeedEA = 50;                     // EA Speed in Milliseconds

// Global Variables
bool isTradingAllowed = true;
bool isDemoAccount = false;
string eaName = "IL BOSS DEL TRADING Scalper";
datetime lastTradeTime = 0;
double initialBalance = 0;
double lastPrice = 0;
datetime drawdownTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize variables
    initialBalance = AccountBalance();
    isDemoAccount = IsDemo();
    
    // Check if trading is allowed
    if(!IsTradeAllowed())
    {
        Print("Trading is not allowed!");
        return(INIT_FAILED);
    }
    
    // Set timer
    if(!EventSetMillisecondTimer(SpeedEA))
    {
        Print("Failed to set timer!");
        return(INIT_FAILED);
    }
    
    // Check digits
    if(_Digits != 5 && _Digits != 3)
    {
        Print("Invalid digits! Only 3 or 5 digits are supported.");
        return(INIT_FAILED);
    }
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    ObjectsDeleteAll(0, 23);
    ObjectsDeleteAll(0, 28);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if trading is allowed
    if(!isTradingAllowed) return;
    
    // Check if demo account
    if(!isDemoAccount) return;
    
    // Check drawdown conditions
    CheckDrawdownConditions();
    
    // Check trading conditions
    if(CheckTradingConditions())
    {
        // Manage open positions
        ManageOpenPositions();
        
        // Open new positions if conditions are met
        OpenNewPositions();
    }
    
    // Update info panel
    if(Info) UpdateInfoPanel();
}

//+------------------------------------------------------------------+
//| Check trading conditions                                          |
//+------------------------------------------------------------------+
bool CheckTradingConditions()
{
    // Check time
    if(!IsTradingTime()) return false;
    
    // Check spread
    double spread = (Ask - Bid) / _Point;
    if(MaxSpread > 0 && spread > MaxSpread) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                     |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
    int currentHour = TimeHour(TimeCurrent());
    return (currentHour >= TimeStart && currentHour < TimeEnd);
}

//+------------------------------------------------------------------+
//| Check drawdown conditions                                         |
//+------------------------------------------------------------------+
void CheckDrawdownConditions()
{
    double totalProfit = CalculateTotalProfit();
    
    // Check percentage drawdown
    if(CloseTradesAtPercentageDrawdown)
    {
        double drawdownPercent = (totalProfit / AccountBalance()) * 100;
        if(drawdownPercent <= -PercentageDrawdown)
        {
            CloseAllPositions("EP Closed At Percentage Drawdown");
            return;
        }
    }
    
    // Check fixed drawdown
    if(CloseTradesAtFixedDrawdown)
    {
        if(totalProfit <= -FixedDrawdown)
        {
            CloseAllPositions("EP Closed At Fixed Drawdown");
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate total profit                                            |
//+------------------------------------------------------------------+
double CalculateTotalProfit()
{
    double total = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == Magic && OrderSymbol() == _Symbol)
            {
                total += OrderProfit() + OrderSwap() + OrderCommission();
            }
        }
    }
    return total;
}

//+------------------------------------------------------------------+
//| Manage open positions                                             |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == Magic && OrderSymbol() == _Symbol)
            {
                // Apply trailing stop
                ApplyTrailingStop();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Apply trailing stop                                               |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
    if(Tral == 0) return;
    
    if(OrderType() == OP_BUY)
    {
        if(OrderStopLoss() < OrderOpenPrice() || OrderStopLoss() == 0)
        {
            double newSL = OrderOpenPrice() + (TralStart * _Point);
            if(Bid - OrderOpenPrice() >= (Tral + TralStart) * _Point)
            {
                OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrGreen);
            }
        }
        else if(Bid - OrderOpenPrice() > Tral * _Point)
        {
            double newSL = Bid - (Tral * _Point);
            if(newSL > OrderStopLoss())
            {
                OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrGreen);
            }
        }
    }
    else if(OrderType() == OP_SELL)
    {
        if(OrderStopLoss() > OrderOpenPrice() || OrderStopLoss() == 0)
        {
            double newSL = OrderOpenPrice() - (TralStart * _Point);
            if(OrderOpenPrice() - Ask >= (Tral + TralStart) * _Point)
            {
                OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrRed);
            }
        }
        else if(OrderOpenPrice() - Ask > Tral * _Point)
        {
            double newSL = Ask + (Tral * _Point);
            if(newSL < OrderStopLoss())
            {
                OrderModify(OrderTicket(), OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrRed);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Open new positions                                                |
//+------------------------------------------------------------------+
void OpenNewPositions()
{
    // Check if we can open new positions
    if(OrdersTotal() >= AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) && AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) != 0)
        return;
        
    // Calculate lot size
    double lotSize = CalculateLotSize();
    
    // Check grid conditions
    if(CheckGridConditions())
    {
        // Open buy position
        if(ShouldOpenBuy())
        {
            OrderSend(_Symbol, OP_BUY, lotSize, Ask, 5, 0, 0, eaName, Magic, 0, clrGreen);
        }
        // Open sell position
        else if(ShouldOpenSell())
        {
            OrderSend(_Symbol, OP_SELL, lotSize, Bid, 5, 0, 0, eaName, Magic, 0, clrRed);
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double lotSize = FixedLots;
    
    if(LotAssignment == AutoMM)
    {
        double riskAmount = PercentageRisk * AccountBalance();
        double pointsValue = PercentageRiskBasedOnPointsMovement * 100;
        lotSize = riskAmount / (pointsValue * MarketInfo(_Symbol, MODE_TICKVALUE));
        
        if(lotSize < MarketInfo(_Symbol, MODE_MINLOT))
            lotSize = MarketInfo(_Symbol, MODE_MINLOT);
    }
    else if(LotAssignment == BalanceRatio)
    {
        lotSize = floor(AccountBalance() / ForEvery) * UseLotsForEveryBalance;
    }
    
    // Normalize lot size
    lotSize = NormalizeDouble(lotSize, 2);
    lotSize = MathMax(lotSize, MarketInfo(_Symbol, MODE_MINLOT));
    lotSize = MathMin(lotSize, MarketInfo(_Symbol, MODE_MAXLOT));
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Check grid conditions                                             |
//+------------------------------------------------------------------+
bool CheckGridConditions()
{
    if(lastTradeTime == 0)
    {
        lastTradeTime = TimeCurrent();
        lastPrice = Bid;
        return true;
    }
    
    if(TimeCurrent() - lastTradeTime >= OpenTime * 60)
    {
        lastTradeTime = TimeCurrent();
        lastPrice = Bid;
        return true;
    }
    
    if(Bid - lastPrice >= PipsStep * _Point)
    {
        lastPrice = Bid;
        return true;
    }
    
    if(lastPrice - Bid >= PipsStep * _Point)
    {
        lastPrice = Bid;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if should open buy position                                 |
//+------------------------------------------------------------------+
bool ShouldOpenBuy()
{
    // Add your buy signal logic here
    return false;
}

//+------------------------------------------------------------------+
//| Check if should open sell position                                |
//+------------------------------------------------------------------+
bool ShouldOpenSell()
{
    // Add your sell signal logic here
    return false;
}

//+------------------------------------------------------------------+
//| Close all positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
    int closedCount = 0;
    
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == Magic && OrderSymbol() == _Symbol && OrderComment() == eaName)
            {
                if(OrderType() == OP_BUY)
                {
                    if(OrderClose(OrderTicket(), OrderLots(), Bid, (int)MarketInfo(_Symbol, MODE_SPREAD), clrWhite))
                    {
                        Print("Buy ticket ", OrderTicket(), " closed");
                        closedCount++;
                    }
                }
                else if(OrderType() == OP_SELL)
                {
                    if(OrderClose(OrderTicket(), OrderLots(), Ask, (int)MarketInfo(_Symbol, MODE_SPREAD), clrWhite))
                    {
                        Print("Sell ticket ", OrderTicket(), " closed");
                        closedCount++;
                    }
                }
                else if(OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
                {
                    if(OrderDelete(OrderTicket()))
                    {
                        Print(OrderType() == OP_BUYSTOP ? "Buy Stop" : "Sell Stop", " Ticket ", OrderTicket(), " deleted");
                        closedCount++;
                    }
                }
            }
        }
    }
    
    if(closedCount > 0)
    {
        isTradingAllowed = false;
        drawdownTime = iTime(NULL, 1440, 0);
        Print("Closed By ", reason);
        
        // Add vertical line
        string vlineName = eaName + TimeToString(TimeCurrent());
        ObjectCreate(0, vlineName, OBJ_VLINE, 0, TimeCurrent(), 0);
        ObjectSet(vlineName, OBJPROP_COLOR, clrYellow);
    }
}

//+------------------------------------------------------------------+
//| Update info panel                                                 |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
    // Create background
    string bgName = "INFO_fon";
    if(ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0))
    {
        ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, 220);
        ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, 20);
        ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 200);
        ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 225);
        ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, FonColor);
        ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, 2);
        ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, clrBlue);
        ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, 1);
        ObjectSetInteger(0, bgName, OBJPROP_HIDDEN, 0);
        ObjectSetInteger(0, bgName, OBJPROP_ZORDER, 0);
    }
    
    // Add logo
    string logoName = "INFO_LOGO";
    ObjectCreate(0, logoName, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, logoName, OBJPROP_XDISTANCE, 165);
    ObjectSetInteger(0, logoName, OBJPROP_YDISTANCE, 24);
    ObjectSetInteger(0, logoName, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, logoName, OBJPROP_TEXT, "www.hadrygassama.com");
    ObjectSetString(0, logoName, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, logoName, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, logoName, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, logoName, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, logoName, OBJPROP_HIDDEN, 0);
    
    // Add separator line
    string lineName = "INFO_Line";
    ObjectCreate(0, lineName, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, lineName, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, lineName, OBJPROP_YDISTANCE, 27);
    ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, lineName, OBJPROP_TEXT, "___________________________");
    ObjectSetString(0, lineName, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, lineName, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, lineName, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, lineName, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, 0);
    
    // Add account information
    string infoTitle = "INFO_txt1";
    ObjectCreate(0, infoTitle, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, infoTitle, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, infoTitle, OBJPROP_YDISTANCE, 45);
    ObjectSetInteger(0, infoTitle, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, infoTitle, OBJPROP_TEXT, "Account information");
    ObjectSetString(0, infoTitle, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, infoTitle, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, infoTitle, OBJPROP_COLOR, InfoDataColor);
    ObjectSetInteger(0, infoTitle, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, infoTitle, OBJPROP_HIDDEN, 0);
    
    // Add minimum stop level
    string minStop = "INFO_txt2";
    ObjectCreate(0, minStop, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, minStop, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, minStop, OBJPROP_YDISTANCE, 65);
    ObjectSetInteger(0, minStop, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, minStop, OBJPROP_TEXT, "Minimum stop:");
    ObjectSetString(0, minStop, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, minStop, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, minStop, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, minStop, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, minStop, OBJPROP_HIDDEN, 0);
    
    // Add minimum stop value
    string minStopValue = "INFO_txt13";
    ObjectCreate(0, minStopValue, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, minStopValue, OBJPROP_XDISTANCE, 85);
    ObjectSetInteger(0, minStopValue, OBJPROP_YDISTANCE, 65);
    ObjectSetInteger(0, minStopValue, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, minStopValue, OBJPROP_TEXT, DoubleToString(MarketInfo(_Symbol, MODE_STOPLEVEL), 0));
    ObjectSetString(0, minStopValue, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, minStopValue, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, minStopValue, OBJPROP_COLOR, InfoDataColor);
    ObjectSetInteger(0, minStopValue, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, minStopValue, OBJPROP_HIDDEN, 0);
    
    // Add current profit percent
    string profitPercent = "INFO_txt3";
    ObjectCreate(0, profitPercent, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, profitPercent, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, profitPercent, OBJPROP_YDISTANCE, 80);
    ObjectSetInteger(0, profitPercent, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, profitPercent, OBJPROP_TEXT, "Current profit percent:");
    ObjectSetString(0, profitPercent, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, profitPercent, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, profitPercent, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, profitPercent, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, profitPercent, OBJPROP_HIDDEN, 0);
    
    // Add current profit percent value
    string profitPercentValue = "INFO_txt14";
    ObjectCreate(0, profitPercentValue, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, profitPercentValue, OBJPROP_XDISTANCE, 85);
    ObjectSetInteger(0, profitPercentValue, OBJPROP_YDISTANCE, 80);
    ObjectSetInteger(0, profitPercentValue, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, profitPercentValue, OBJPROP_TEXT, DoubleToString(CalculateProfitPercent(), 2));
    ObjectSetString(0, profitPercentValue, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, profitPercentValue, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, profitPercentValue, OBJPROP_COLOR, InfoDataColor);
    ObjectSetInteger(0, profitPercentValue, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, profitPercentValue, OBJPROP_HIDDEN, 0);
    
    // Add balance
    string balance = "INFO_txt4";
    ObjectCreate(0, balance, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, balance, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, balance, OBJPROP_YDISTANCE, 95);
    ObjectSetInteger(0, balance, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, balance, OBJPROP_TEXT, "Balance:");
    ObjectSetString(0, balance, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, balance, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, balance, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, balance, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, balance, OBJPROP_HIDDEN, 0);
    
    // Add balance value
    string balanceValue = "INFO_txt15";
    ObjectCreate(0, balanceValue, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, balanceValue, OBJPROP_XDISTANCE, 85);
    ObjectSetInteger(0, balanceValue, OBJPROP_YDISTANCE, 95);
    ObjectSetInteger(0, balanceValue, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, balanceValue, OBJPROP_TEXT, DoubleToString(AccountBalance(), 2));
    ObjectSetString(0, balanceValue, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, balanceValue, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, balanceValue, OBJPROP_COLOR, InfoDataColor);
    ObjectSetInteger(0, balanceValue, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, balanceValue, OBJPROP_HIDDEN, 0);
    
    // Add equity
    string equity = "INFO_txt5";
    ObjectCreate(0, equity, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, equity, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, equity, OBJPROP_YDISTANCE, 110);
    ObjectSetInteger(0, equity, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, equity, OBJPROP_TEXT, "Equity:");
    ObjectSetString(0, equity, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, equity, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, equity, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, equity, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, equity, OBJPROP_HIDDEN, 0);
    
    // Add equity value
    string equityValue = "INFO_txt16";
    ObjectCreate(0, equityValue, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, equityValue, OBJPROP_XDISTANCE, 85);
    ObjectSetInteger(0, equityValue, OBJPROP_YDISTANCE, 110);
    ObjectSetInteger(0, equityValue, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, equityValue, OBJPROP_TEXT, DoubleToString(AccountEquity(), 2));
    ObjectSetString(0, equityValue, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, equityValue, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, equityValue, OBJPROP_COLOR, InfoDataColor);
    ObjectSetInteger(0, equityValue, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, equityValue, OBJPROP_HIDDEN, 0);
    
    // Add profit on pair
    string pairProfit = "INFO_txt7";
    ObjectCreate(0, pairProfit, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, pairProfit, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, pairProfit, OBJPROP_YDISTANCE, 150);
    ObjectSetInteger(0, pairProfit, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, pairProfit, OBJPROP_TEXT, "Profit on pair:");
    ObjectSetString(0, pairProfit, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, pairProfit, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, pairProfit, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, pairProfit, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, pairProfit, OBJPROP_HIDDEN, 0);
    
    // Add profit on pair value
    string pairProfitValue = "INFO_txt17";
    ObjectCreate(0, pairProfitValue, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, pairProfitValue, OBJPROP_XDISTANCE, 85);
    ObjectSetInteger(0, pairProfitValue, OBJPROP_YDISTANCE, 150);
    ObjectSetInteger(0, pairProfitValue, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, pairProfitValue, OBJPROP_TEXT, DoubleToString(CalculatePairProfit(), 2));
    ObjectSetString(0, pairProfitValue, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, pairProfitValue, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, pairProfitValue, OBJPROP_COLOR, InfoDataColor);
    ObjectSetInteger(0, pairProfitValue, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, pairProfitValue, OBJPROP_HIDDEN, 0);
    
    // Add total profit
    string totalProfit = "INFO_txt8";
    ObjectCreate(0, totalProfit, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, totalProfit, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, totalProfit, OBJPROP_YDISTANCE, 165);
    ObjectSetInteger(0, totalProfit, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, totalProfit, OBJPROP_TEXT, "Total profit:");
    ObjectSetString(0, totalProfit, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, totalProfit, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, totalProfit, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, totalProfit, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, totalProfit, OBJPROP_HIDDEN, 0);
    
    // Add total profit value
    string totalProfitValue = "INFO_txt18";
    ObjectCreate(0, totalProfitValue, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, totalProfitValue, OBJPROP_XDISTANCE, 85);
    ObjectSetInteger(0, totalProfitValue, OBJPROP_YDISTANCE, 165);
    ObjectSetInteger(0, totalProfitValue, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, totalProfitValue, OBJPROP_TEXT, DoubleToString(CalculateTotalProfit(), 2));
    ObjectSetString(0, totalProfitValue, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, totalProfitValue, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, totalProfitValue, OBJPROP_COLOR, InfoDataColor);
    ObjectSetInteger(0, totalProfitValue, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, totalProfitValue, OBJPROP_HIDDEN, 0);
    
    // Add today's profit
    string todayProfit = "INFO_txt9";
    ObjectCreate(0, todayProfit, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, todayProfit, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, todayProfit, OBJPROP_YDISTANCE, 180);
    ObjectSetInteger(0, todayProfit, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, todayProfit, OBJPROP_TEXT, "Profit for today:");
    ObjectSetString(0, todayProfit, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, todayProfit, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, todayProfit, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, todayProfit, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, todayProfit, OBJPROP_HIDDEN, 0);
    
    // Add today's profit value
    string todayProfitValue = "INFO_txt19";
    ObjectCreate(0, todayProfitValue, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, todayProfitValue, OBJPROP_XDISTANCE, 85);
    ObjectSetInteger(0, todayProfitValue, OBJPROP_YDISTANCE, 180);
    ObjectSetInteger(0, todayProfitValue, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, todayProfitValue, OBJPROP_TEXT, DoubleToString(CalculateTodayProfit(), 2));
    ObjectSetString(0, todayProfitValue, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, todayProfitValue, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, todayProfitValue, OBJPROP_COLOR, InfoDataColor);
    ObjectSetInteger(0, todayProfitValue, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, todayProfitValue, OBJPROP_HIDDEN, 0);
    
    // Add yesterday's profit
    string yesterdayProfit = "INFO_txt10";
    ObjectCreate(0, yesterdayProfit, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, yesterdayProfit, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, yesterdayProfit, OBJPROP_YDISTANCE, 195);
    ObjectSetInteger(0, yesterdayProfit, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, yesterdayProfit, OBJPROP_TEXT, "Profit for yesterday:");
    ObjectSetString(0, yesterdayProfit, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, yesterdayProfit, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, yesterdayProfit, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, yesterdayProfit, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, yesterdayProfit, OBJPROP_HIDDEN, 0);
    
    // Add yesterday's profit value
    string yesterdayProfitValue = "INFO_txt20";
    ObjectCreate(0, yesterdayProfitValue, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, yesterdayProfitValue, OBJPROP_XDISTANCE, 85);
    ObjectSetInteger(0, yesterdayProfitValue, OBJPROP_YDISTANCE, 195);
    ObjectSetInteger(0, yesterdayProfitValue, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, yesterdayProfitValue, OBJPROP_TEXT, DoubleToString(CalculateYesterdayProfit(), 2));
    ObjectSetString(0, yesterdayProfitValue, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, yesterdayProfitValue, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, yesterdayProfitValue, OBJPROP_COLOR, InfoDataColor);
    ObjectSetInteger(0, yesterdayProfitValue, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, yesterdayProfitValue, OBJPROP_HIDDEN, 0);
    
    // Add week's profit
    string weekProfit = "INFO_txt11";
    ObjectCreate(0, weekProfit, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, weekProfit, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, weekProfit, OBJPROP_YDISTANCE, 210);
    ObjectSetInteger(0, weekProfit, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, weekProfit, OBJPROP_TEXT, "Profit for week:");
    ObjectSetString(0, weekProfit, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, weekProfit, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, weekProfit, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, weekProfit, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, weekProfit, OBJPROP_HIDDEN, 0);
    
    // Add week's profit value
    string weekProfitValue = "INFO_txt21";
    ObjectCreate(0, weekProfitValue, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, weekProfitValue, OBJPROP_XDISTANCE, 85);
    ObjectSetInteger(0, weekProfitValue, OBJPROP_YDISTANCE, 210);
    ObjectSetInteger(0, weekProfitValue, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, weekProfitValue, OBJPROP_TEXT, DoubleToString(CalculateWeekProfit(), 2));
    ObjectSetString(0, weekProfitValue, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, weekProfitValue, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, weekProfitValue, OBJPROP_COLOR, InfoDataColor);
    ObjectSetInteger(0, weekProfitValue, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, weekProfitValue, OBJPROP_HIDDEN, 0);
    
    // Add month's profit
    string monthProfit = "INFO_txt12";
    ObjectCreate(0, monthProfit, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, monthProfit, OBJPROP_XDISTANCE, 215);
    ObjectSetInteger(0, monthProfit, OBJPROP_YDISTANCE, 225);
    ObjectSetInteger(0, monthProfit, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, monthProfit, OBJPROP_TEXT, "Profit for month:");
    ObjectSetString(0, monthProfit, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, monthProfit, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, monthProfit, OBJPROP_COLOR, TextColor);
    ObjectSetInteger(0, monthProfit, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, monthProfit, OBJPROP_HIDDEN, 0);
    
    // Add month's profit value
    string monthProfitValue = "INFO_txt22";
    ObjectCreate(0, monthProfitValue, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, monthProfitValue, OBJPROP_XDISTANCE, 85);
    ObjectSetInteger(0, monthProfitValue, OBJPROP_YDISTANCE, 225);
    ObjectSetInteger(0, monthProfitValue, OBJPROP_SELECTABLE, 1);
    ObjectSetString(0, monthProfitValue, OBJPROP_TEXT, DoubleToString(CalculateMonthProfit(), 2));
    ObjectSetString(0, monthProfitValue, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, monthProfitValue, OBJPROP_FONTSIZE, FontSizeInfo);
    ObjectSetInteger(0, monthProfitValue, OBJPROP_COLOR, InfoDataColor);
    ObjectSetInteger(0, monthProfitValue, OBJPROP_ZORDER, 0);
    ObjectSetInteger(0, monthProfitValue, OBJPROP_HIDDEN, 0);
}

//+------------------------------------------------------------------+
//| Calculate profit percent                                          |
//+------------------------------------------------------------------+
double CalculateProfitPercent()
{
    double totalProfit = CalculateTotalProfit();
    return (totalProfit / AccountBalance()) * 100;
}

//+------------------------------------------------------------------+
//| Calculate pair profit                                             |
//+------------------------------------------------------------------+
double CalculatePairProfit()
{
    double profit = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if(OrderMagicNumber() == Magic && OrderSymbol() == _Symbol)
            {
                profit += OrderProfit() + OrderSwap() + OrderCommission();
            }
        }
    }
    return profit;
}

//+------------------------------------------------------------------+
//| Calculate today's profit                                          |
//+------------------------------------------------------------------+
double CalculateTodayProfit()
{
    double profit = 0;
    for(int i = HistoryTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        {
            if(OrderMagicNumber() == Magic && OrderCloseTime() >= iTime(_Symbol, 1440, 0))
            {
                profit += OrderProfit() + OrderSwap() + OrderCommission();
            }
        }
    }
    return profit;
}

//+------------------------------------------------------------------+
//| Calculate yesterday's profit                                      |
//+------------------------------------------------------------------+
double CalculateYesterdayProfit()
{
    double profit = 0;
    for(int i = HistoryTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        {
            if(OrderMagicNumber() == Magic)
            {
                datetime closeTime = OrderCloseTime();
                if(closeTime >= iTime(_Symbol, 1440, 1) && closeTime < iTime(_Symbol, 1440, 0))
                {
                    profit += OrderProfit() + OrderSwap() + OrderCommission();
                }
            }
        }
    }
    return profit;
}

//+------------------------------------------------------------------+
//| Calculate week's profit                                           |
//+------------------------------------------------------------------+
double CalculateWeekProfit()
{
    double profit = 0;
    for(int i = HistoryTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        {
            if(OrderMagicNumber() == Magic && OrderCloseTime() >= iTime(_Symbol, 10080, 0))
            {
                profit += OrderProfit() + OrderSwap() + OrderCommission();
            }
        }
    }
    return profit;
}

//+------------------------------------------------------------------+
//| Calculate month's profit                                          |
//+------------------------------------------------------------------+
double CalculateMonthProfit()
{
    double profit = 0;
    for(int i = HistoryTotal() - 1; i >= 0; i--)
    {
        if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
        {
            if(OrderMagicNumber() == Magic && OrderCloseTime() >= iTime(_Symbol, 43200, 0))
            {
                profit += OrderProfit() + OrderSwap() + OrderCommission();
            }
        }
    }
    return profit;
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
    RefreshRates();
    OnTick();
}


