//+------------------------------------------------------------------+
//|                                                      ProfitableEA.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Includes
#include <Trade\Trade.mqh>
#include <Indicators\Indicators.mqh>
#include <Arrays\ArrayString.mqh>
#include <Arrays\ArrayObj.mqh>
#include <stdlib.mqh>
#include <stderror.mqh>

// Ensure all necessary includes for string and datetime handling
#include <string.mqh>
#include <datetime.mqh>

// Enumérations
enum ENUM_TRADE_DIRECTION {
   TRADE_BUY = 0,    // Trading Buy only
   TRADE_SELL = 1,   // Trading Sell only
   TRADE_BOTH = 2    // Trading both directions
};

enum ENUM_EXIT_METHOD {
   EXIT_RR = 0,      // Exit based on Risk/Reward ratio
   EXIT_EMA = 1,     // Exit based on EMA crossover
   EXIT_BOTH = 2     // Exit based on both conditions
};

// Structure pour les heures des annonces
struct NewsTime {
   int hour;         // Heure de l'annonce (UTC)
   int minute;       // Minute de l'annonce (UTC)
   string name;      // Nom de l'annonce
   int dayOfWeek;    // Jour de la semaine (0-6, -1 pour tous les jours)
   int dayOfMonth;   // Jour du mois (1-31, -1 pour tous les jours)
};

// Structure pour stocker les informations par paire
struct SymbolData {
   string symbol;
   CTrade trade;
   datetime lastTradeTime;
   int dailyTradesCount;
   datetime lastTradeDate;
   datetime lastSignalTime;    // Time of the last EMA crossover signal
   double crossoverPrice;      // Price at the time of crossover
   bool signalConfirmed;       // Whether the signal is confirmed by candle close
   double retracementLevel;    // Price level for retracement confirmation
   
   // Handles des indicateurs
   int emaFastHandle;    // EMA 10 H1
   int emaSlowHandle;    // EMA 20 H1
   int emaFastH4Handle;  // EMA 9 H4
   int emaSlowH4Handle;  // EMA 21 H4
   int adxHandle;        // ADX
   int volumeHandle;     // Volume
   int volOscHandle;     // Volume Oscillator
   int atrHandle;        // ATR pour le buffer du stop loss
   int ema100Handle;      // EMA 100 H1
   int ema200Handle;      // EMA 200 H1
   
   // Valeurs des indicateurs
   double lastFastEMA;
   double lastSlowEMA;
   double lastFastEMAH4;
   double lastSlowEMAH4;
   double lastADX;
   double lastVolume;
   double lastVolOsc;
   double lastATR;
   double lastEMA100;
   double lastEMA200;
   
   // États des signaux
   bool emaCrossedUp;
   bool emaCrossedDown;
   bool trendConfirmed;
   bool retracementConfirmed;
};

// Structure pour les données de news Forex Factory
struct NewsEvent {
   string title;      // Title of the news event
   string country;    // Country code
   datetime time;     // Event time
   string impact;     // Impact level (High, Medium, Low)
   string currency;   // Currency affected
   string forecast;   // Forecasted value
   string previous;   // Previous value
};

// Paramètres d'entrée
input group "=== Configuration Générale ==="
input string   TradingPairs = "EURUSD,GBPUSD,USDJPY,AUDUSD,EURGBP";  // Pairs to trade
input int      Magic = 123456;         // EA ID
input bool     ShowTradeLogs = true;   // Show logs

input group "=== Gestion du Capital ==="
input double   RiskPercent = 1.0;      // Risk per trade (%)
input double   RiskRewardRatio = 2.0;  // Risk/Reward ratio

input group "=== Paramètres EMA H1 ==="
input int      EMAPeriodFast = 10;     // Fast EMA period
input int      EMAPeriodSlow = 20;     // Slow EMA period

input group "=== Paramètres EMA H4 ==="
input int      EMAPeriodFastH4 = 9;    // Fast EMA period
input int      EMAPeriodSlowH4 = 21;   // Slow EMA period

input group "=== Paramètres ADX ==="
input int      ADXPeriod = 14;         // ADX period
input double   ADXThreshold = 25;      // ADX threshold for trend
input double   ADXMinThreshold = 20;   // ADX minimum threshold

input group "=== Paramètres Volume ==="
input int      VolOscFastPeriod = 5;   // Volume Oscillator fast period
input int      VolOscSlowPeriod = 10;  // Volume Oscillator slow period
input double   VolOscThreshold = 0.0;  // Volume Oscillator threshold

input group "=== Paramètres Stop Loss ==="
input int      SwingPeriods = 20;      // Periods to look back for swing points
input int      ATRPeriod = 14;         // ATR period for stop loss buffer
input double   ATRMultiplier = 1.5;    // ATR multiplier for stop loss buffer

input group "=== Paramètres Retracement ==="
input double   RetracementThreshold = 0.5;  // Minimum retracement percentage (0.5 = 50%)
input int      MaxRetracementBars = 5;      // Maximum bars to wait for retracement

input group "=== Paramètres de Trading ==="
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_BOTH;  // Direction
input ENUM_EXIT_METHOD ExitMethod = EXIT_BOTH;          // Exit method
input int      MaxSpread = 50;         // Max spread
input int      MaxDailyTrades = 10;    // Max trades/day

input group "=== Paramètres News ==="
input bool     AvoidNews = true;       // Avoid trading during news
input int      NewsMinutesBefore = 30; // Minutes before news to avoid
input int      NewsMinutesAfter = 30;  // Minutes after news to avoid
input bool     MonitorUSD = true;      // Monitor USD news
input bool     MonitorEUR = true;      // Monitor EUR news
input bool     MonitorGBP = true;      // Monitor GBP news
input bool     MonitorJPY = true;      // Monitor JPY news
input bool     MonitorAUD = true;      // Monitor AUD news
input bool     MonitorNZD = true;      // Monitor NZD news
input bool     MonitorCAD = true;      // Monitor CAD news
input bool     MonitorCHF = true;      // Monitor CHF news

// Variables globales
SymbolData symbols[];
int totalSymbols = 0;

// Tableau des heures des annonces majeures (heure UTC)
NewsTime majorNewsTimes[] = {
   {13, 30, "NFP", 5, -1},           // Non-Farm Payrolls (1er vendredi du mois)
   {14, 00, "FOMC", -1, -1},         // Décision de taux FED
   {12, 00, "ECB", -1, -1},          // Décision de taux BCE
   {11, 00, "BOE", -1, -1},          // Décision de taux BOE
   {11, 30, "BOJ", -1, -1},          // Décision de taux BOJ
   {13, 15, "ADP", -1, -1},          // ADP Employment Change
   {12, 30, "CPI", -1, -1},          // Consumer Price Index
   {12, 30, "GDP", -1, -1},          // GDP
   {12, 30, "Retail Sales", -1, -1}  // Retail Sales
};

// Global variables for Forex Factory API
string FF_API_URL = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml";
NewsEvent newsEvents[];

//+------------------------------------------------------------------+
//| Récupération des événements du calendrier                         |
//+------------------------------------------------------------------+
bool FetchNewsEvents() {
   string headers = "Content-Type: application/xml\r\n";
   char data[], result[];
   
   int res = WebRequest("GET", FF_API_URL, headers, 5000, data, result, headers);
   
   if(res != 200) {
      Print("Erreur lors de la récupération des news. Code: ", res);
      return false;
   }
   
   string response = CharArrayToString(result);
   return ParseNewsEvents(response);
}

//+------------------------------------------------------------------+
//| Parse la réponse XML des événements                              |
//+------------------------------------------------------------------+
bool ParseNewsEvents(string xmlResponse) {
   // Réinitialiser le tableau des événements
   ArrayFree(newsEvents);
   
   // Parser le XML
   int start = 0;
   int count = 0;
   
   while(true) {
      // Trouver le début d'un événement
      start = StringFind(xmlResponse, "<event", start);
      if(start == -1) break;
      
      // Extraire les données de l'événement
      NewsEvent event;
      
      // Titre
      int titleStart = StringFind(xmlResponse, "<title>", start) + 7;
      int titleEnd = StringFind(xmlResponse, "</title>", titleStart);
      if(titleStart > 6 && titleEnd > titleStart) {
         event.title = StringSubstr(xmlResponse, titleStart, titleEnd - titleStart);
      }
      
      // Pays
      int countryStart = StringFind(xmlResponse, "<country>", start) + 9;
      int countryEnd = StringFind(xmlResponse, "</country>", countryStart);
      if(countryStart > 8 && countryEnd > countryStart) {
         event.country = StringSubstr(xmlResponse, countryStart, countryEnd - countryStart);
      }
      
      // Date et heure
      int dateStart = StringFind(xmlResponse, "<date>", start) + 6;
      int dateEnd = StringFind(xmlResponse, "</date>", dateStart);
      if(dateStart > 5 && dateEnd > dateStart) {
         string dateStr = StringSubstr(xmlResponse, dateStart, dateEnd - dateStart);
         event.time = StringToTime(dateStr);
      }
      
      // Impact
      int impactStart = StringFind(xmlResponse, "<impact>", start) + 8;
      int impactEnd = StringFind(xmlResponse, "</impact>", impactStart);
      if(impactStart > 7 && impactEnd > impactStart) {
         event.impact = StringSubstr(xmlResponse, impactStart, impactEnd - impactStart);
      }
      
      // Devise
      int currencyStart = StringFind(xmlResponse, "<currency>", start) + 10;
      int currencyEnd = StringFind(xmlResponse, "</currency>", currencyStart);
      if(currencyStart > 9 && currencyEnd > currencyStart) {
         event.currency = StringSubstr(xmlResponse, currencyStart, currencyEnd - currencyStart);
      }
      
      // Prévision
      int forecastStart = StringFind(xmlResponse, "<forecast>", start) + 10;
      int forecastEnd = StringFind(xmlResponse, "</forecast>", forecastStart);
      if(forecastStart > 9 && forecastEnd > forecastStart) {
         event.forecast = StringSubstr(xmlResponse, forecastStart, forecastEnd - forecastStart);
      }
      
      // Valeur précédente
      int previousStart = StringFind(xmlResponse, "<previous>", start) + 10;
      int previousEnd = StringFind(xmlResponse, "</previous>", previousStart);
      if(previousStart > 9 && previousEnd > previousStart) {
         event.previous = StringSubstr(xmlResponse, previousStart, previousEnd - previousStart);
      }
      
      // Ajouter l'événement au tableau
      ArrayResize(newsEvents, count + 1);
      newsEvents[count] = event;
      count++;
      
      start = StringFind(xmlResponse, "</event>", start) + 8;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Vérification de l'impact d'une news                               |
//+------------------------------------------------------------------+
int GetNewsImpact(string impact) {
   if(impact == "High") return 3;
   if(impact == "Medium") return 2;
   if(impact == "Low") return 1;
   return 0;
}

//+------------------------------------------------------------------+
//| Vérifie si on est proche d'une news importante                    |
//+------------------------------------------------------------------+
bool IsNewsTime() {
   if(!AvoidNews) return false;
   
   datetime current = TimeCurrent();
   
   // Vérifier les news de Forex Factory
   for(int i = 0; i < ArraySize(newsEvents); i++) {
      // Vérifier si la devise est surveillée
      bool monitorCurrency = false;
      if(newsEvents[i].currency == "USD" && MonitorUSD) monitorCurrency = true;
      else if(newsEvents[i].currency == "EUR" && MonitorEUR) monitorCurrency = true;
      else if(newsEvents[i].currency == "GBP" && MonitorGBP) monitorCurrency = true;
      else if(newsEvents[i].currency == "JPY" && MonitorJPY) monitorCurrency = true;
      else if(newsEvents[i].currency == "AUD" && MonitorAUD) monitorCurrency = true;
      else if(newsEvents[i].currency == "NZD" && MonitorNZD) monitorCurrency = true;
      else if(newsEvents[i].currency == "CAD" && MonitorCAD) monitorCurrency = true;
      else if(newsEvents[i].currency == "CHF" && MonitorCHF) monitorCurrency = true;
      
      if(monitorCurrency && GetNewsImpact(newsEvents[i].impact) >= 2) {  // Medium ou High impact
         int timeDiff = (int)MathAbs(newsEvents[i].time - current);
         int bufferSeconds = (NewsMinutesBefore + NewsMinutesAfter) * 60;
         
         if(timeDiff <= bufferSeconds) {
            Print("News importante détectée: ", newsEvents[i].title, " à ", TimeToString(newsEvents[i].time));
            return true;
         }
      }
   }
   
   // Garder la vérification des heures fixes comme backup
   MqlDateTime currentTime;
   TimeToStruct(current, currentTime);
   int currentMinutes = currentTime.hour * 60 + currentTime.min;
   
   for(int i = 0; i < ArraySize(majorNewsTimes); i++) {
      if(majorNewsTimes[i].dayOfWeek != -1 && currentTime.day_of_week != majorNewsTimes[i].dayOfWeek) continue;
      if(majorNewsTimes[i].dayOfMonth != -1 && currentTime.day != majorNewsTimes[i].dayOfMonth) continue;
      
      int newsMinutes = majorNewsTimes[i].hour * 60 + majorNewsTimes[i].minute;
      int timeDiff = MathAbs(currentMinutes - newsMinutes);
      
      if(timeDiff <= NewsMinutesBefore || timeDiff <= NewsMinutesAfter) {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Draw vertical lines for news events                               |
//+------------------------------------------------------------------+
void DrawNewsLines() {
   if(!AvoidNews) return;
   
   // Supprimer les anciennes lignes
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--) {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, "NewsLine_") == 0) {
         ObjectDelete(0, name);
      }
   }
   
   // Dessiner les nouvelles lignes
   for(int i = 0; i < ArraySize(newsEvents); i++) {
      // Vérifier si la devise est surveillée
      bool monitorCurrency = false;
      if(newsEvents[i].currency == "USD" && MonitorUSD) monitorCurrency = true;
      else if(newsEvents[i].currency == "EUR" && MonitorEUR) monitorCurrency = true;
      else if(newsEvents[i].currency == "GBP" && MonitorGBP) monitorCurrency = true;
      else if(newsEvents[i].currency == "JPY" && MonitorJPY) monitorCurrency = true;
      else if(newsEvents[i].currency == "AUD" && MonitorAUD) monitorCurrency = true;
      else if(newsEvents[i].currency == "NZD" && MonitorNZD) monitorCurrency = true;
      else if(newsEvents[i].currency == "CAD" && MonitorCAD) monitorCurrency = true;
      else if(newsEvents[i].currency == "CHF" && MonitorCHF) monitorCurrency = true;
      
      if(monitorCurrency && GetNewsImpact(newsEvents[i].impact) >= 2) {
         string lineName = "NewsLine_" + IntegerToString(i);
         color lineColor = clrRed;
         
         if(newsEvents[i].impact == "High") {
            lineColor = clrRed;
         } else if(newsEvents[i].impact == "Medium") {
            lineColor = clrOrange;
         } else {
            lineColor = clrYellow;
         }
         
         if(ObjectCreate(0, lineName, OBJ_VLINE, 0, newsEvents[i].time, 0)) {
            ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
            ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, lineName, OBJPROP_BACK, true);
            ObjectSetString(0, lineName, OBJPROP_TEXT, newsEvents[i].title + " (" + newsEvents[i].currency + ")");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                      |
//+------------------------------------------------------------------+
int OnInit() {
   // Initialiser les paires de trading
   string pairs[];
   StringSplit(TradingPairs, ',', pairs);
   totalSymbols = ArraySize(pairs);
   ArrayResize(symbols, totalSymbols);
   
   for(int i = 0; i < totalSymbols; i++) {
      symbols[i].symbol = pairs[i];
      symbols[i].trade.SetExpertMagicNumber(Magic);
      symbols[i].lastTradeTime = 0;
      symbols[i].dailyTradesCount = 0;
      symbols[i].lastTradeDate = 0;
      symbols[i].lastSignalTime = 0;
      symbols[i].crossoverPrice = 0;
      symbols[i].signalConfirmed = false;
      symbols[i].retracementLevel = 0;
      
      // Initialiser les indicateurs
      symbols[i].emaFastHandle = iMA(symbols[i].symbol, PERIOD_H1, EMAPeriodFast, 0, MODE_EMA, PRICE_CLOSE);
      symbols[i].emaSlowHandle = iMA(symbols[i].symbol, PERIOD_H1, EMAPeriodSlow, 0, MODE_EMA, PRICE_CLOSE);
      symbols[i].emaFastH4Handle = iMA(symbols[i].symbol, PERIOD_H4, EMAPeriodFastH4, 0, MODE_EMA, PRICE_CLOSE);
      symbols[i].emaSlowH4Handle = iMA(symbols[i].symbol, PERIOD_H4, EMAPeriodSlowH4, 0, MODE_EMA, PRICE_CLOSE);
      symbols[i].adxHandle = iADX(symbols[i].symbol, PERIOD_H1, ADXPeriod);
      symbols[i].volumeHandle = iVolumes(symbols[i].symbol, PERIOD_H1, VOLUME_TICK);
      symbols[i].volOscHandle = iCustom(symbols[i].symbol, PERIOD_H1, "Volume Oscillator", VolOscFastPeriod, VolOscSlowPeriod);
      symbols[i].atrHandle = iATR(symbols[i].symbol, PERIOD_H1, ATRPeriod);
      symbols[i].ema100Handle = iMA(symbols[i].symbol, PERIOD_H1, 100, 0, MODE_EMA, PRICE_CLOSE);
      symbols[i].ema200Handle = iMA(symbols[i].symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
      
      if(symbols[i].emaFastHandle == INVALID_HANDLE || 
         symbols[i].emaSlowHandle == INVALID_HANDLE ||
         symbols[i].emaFastH4Handle == INVALID_HANDLE ||
         symbols[i].emaSlowH4Handle == INVALID_HANDLE ||
         symbols[i].adxHandle == INVALID_HANDLE ||
         symbols[i].volumeHandle == INVALID_HANDLE ||
         symbols[i].volOscHandle == INVALID_HANDLE ||
         symbols[i].atrHandle == INVALID_HANDLE ||
         symbols[i].ema100Handle == INVALID_HANDLE ||
         symbols[i].ema200Handle == INVALID_HANDLE) {
         PrintFormat("Error creating indicators for %s", symbols[i].symbol);
         return INIT_FAILED;
      }
      
      symbols[i].emaCrossedUp = false;
      symbols[i].emaCrossedDown = false;
      symbols[i].trendConfirmed = false;
      symbols[i].retracementConfirmed = false;
   }
   
   PrintFormat("EA initialized - Magic: %d", Magic);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   // Libérer les handles des indicateurs
   for(int i = 0; i < totalSymbols; i++) {
      if(symbols[i].emaFastHandle != INVALID_HANDLE) IndicatorRelease(symbols[i].emaFastHandle);
      if(symbols[i].emaSlowHandle != INVALID_HANDLE) IndicatorRelease(symbols[i].emaSlowHandle);
      if(symbols[i].emaFastH4Handle != INVALID_HANDLE) IndicatorRelease(symbols[i].emaFastH4Handle);
      if(symbols[i].emaSlowH4Handle != INVALID_HANDLE) IndicatorRelease(symbols[i].emaSlowH4Handle);
      if(symbols[i].adxHandle != INVALID_HANDLE) IndicatorRelease(symbols[i].adxHandle);
      if(symbols[i].volumeHandle != INVALID_HANDLE) IndicatorRelease(symbols[i].volumeHandle);
      if(symbols[i].volOscHandle != INVALID_HANDLE) IndicatorRelease(symbols[i].volOscHandle);
      if(symbols[i].atrHandle != INVALID_HANDLE) IndicatorRelease(symbols[i].atrHandle);
      if(symbols[i].ema100Handle != INVALID_HANDLE) IndicatorRelease(symbols[i].ema100Handle);
      if(symbols[i].ema200Handle != INVALID_HANDLE) IndicatorRelease(symbols[i].ema200Handle);
   }
   
   PrintFormat("EA deinitialized - Reason: %d", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick() {
   // Rafraîchir les news toutes les heures
   static datetime lastNewsUpdate = 0;
   if(TimeCurrent() - lastNewsUpdate >= 3600) {  // Mise à jour toutes les heures
      if(FetchNewsEvents()) {
         lastNewsUpdate = TimeCurrent();
         DrawNewsLines();  // Mettre à jour les lignes après chaque mise à jour des news
      }
   }
   
   // Traiter chaque paire
   for(int i = 0; i < totalSymbols; i++) {
      ProcessSymbol(symbols[i]);
   }
}

//+------------------------------------------------------------------+
//| Check if current time is near major news                          |
//+------------------------------------------------------------------+
bool IsNewsTime() {
   if(!AvoidNews) return false;
   
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   
   // Vérifier d'abord les news de l'API
   for(int i = 0; i < ArraySize(newsEvents); i++) {
      if(newsEvents[i].impact >= 2) {  // Seulement les news à fort impact
         datetime newsTime = newsEvents[i].time;
         datetime current = TimeCurrent();
         
         if(MathAbs(newsTime - current) <= (NewsMinutesBefore + NewsMinutesAfter) * 60) {
            return true;
         }
      }
   }
   
   // Vérifier ensuite les heures fixes (comme backup)
   int currentMinutes = currentTime.hour * 60 + currentTime.min;
   
   for(int i = 0; i < ArraySize(majorNewsTimes); i++) {
      if(majorNewsTimes[i].dayOfWeek != -1 && currentTime.day_of_week != majorNewsTimes[i].dayOfWeek) {
         continue;
      }
      
      if(majorNewsTimes[i].dayOfMonth != -1 && currentTime.day != majorNewsTimes[i].dayOfMonth) {
         continue;
      }
      
      int newsMinutes = majorNewsTimes[i].hour * 60 + majorNewsTimes[i].minute;
      int timeDiff = MathAbs(currentMinutes - newsMinutes);
      
      if(timeDiff <= NewsMinutesBefore || timeDiff <= NewsMinutesAfter) {
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check retracement condition                                        |
//+------------------------------------------------------------------+
bool CheckRetracement(SymbolData &symbol, bool isLong) {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(symbol.symbol, PERIOD_H1, 0, MaxRetracementBars, rates) <= 0) {
      return false;
   }
   
   double emaSlowBuffer[];
   ArraySetAsSeries(emaSlowBuffer, true);
   
   if(CopyBuffer(symbol.emaSlowHandle, 0, 0, MaxRetracementBars, emaSlowBuffer) <= 0) {
      return false;
   }
   
   // Calculate the move size from crossover to current
   double moveSize = MathAbs(symbol.crossoverPrice - emaSlowBuffer[0]);
   
   if(isLong) {
      // For long positions, check if price has retraced to EMA 20
      for(int i = 0; i < MaxRetracementBars; i++) {
         double retracementSize = MathAbs(rates[i].low - emaSlowBuffer[i]);
         double retracementPercent = retracementSize / moveSize;
         
         if(ShowTradeLogs) {
            PrintFormat("[%s] Retracement check - Bar: %d, Low: %.5f, EMA20: %.5f, Retracement: %.2f%%", 
                      symbol.symbol, i, rates[i].low, emaSlowBuffer[i], retracementPercent * 100);
         }
         
         if(retracementPercent >= RetracementThreshold) {
            symbol.retracementLevel = rates[i].low;
            return true;
         }
      }
   } else {
      // For short positions, check if price has retraced to EMA 20
      for(int i = 0; i < MaxRetracementBars; i++) {
         double retracementSize = MathAbs(rates[i].high - emaSlowBuffer[i]);
         double retracementPercent = retracementSize / moveSize;
         
         if(ShowTradeLogs) {
            PrintFormat("[%s] Retracement check - Bar: %d, High: %.5f, EMA20: %.5f, Retracement: %.2f%%", 
                      symbol.symbol, i, rates[i].high, emaSlowBuffer[i], retracementPercent * 100);
         }
         
         if(retracementPercent >= RetracementThreshold) {
            symbol.retracementLevel = rates[i].high;
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Find swing high/low points with ATR buffer                         |
//+------------------------------------------------------------------+
double FindSwingHigh(string symbol, int periods, double atr) {
   double high = 0;
   for(int i = 1; i <= periods; i++) {
      double currentHigh = iHigh(symbol, PERIOD_H1, i);
      if(currentHigh > high) high = currentHigh;
   }
   return high + (atr * ATRMultiplier);
}

double FindSwingLow(string symbol, int periods, double atr) {
   double low = DBL_MAX;
   for(int i = 1; i <= periods; i++) {
      double currentLow = iLow(symbol, PERIOD_H1, i);
      if(currentLow < low) low = currentLow;
   }
   return low - (atr * ATRMultiplier);
}

//+------------------------------------------------------------------+
//| Check if we should exit based on EMA crossover                     |
//+------------------------------------------------------------------+
bool ShouldExitOnEMACrossover(SymbolData &symbol, bool isLong) {
   double emaFastBuffer[], emaSlowBuffer[];
   ArraySetAsSeries(emaFastBuffer, true);
   ArraySetAsSeries(emaSlowBuffer, true);
   
   if(CopyBuffer(symbol.emaFastHandle, 0, 0, 2, emaFastBuffer) <= 0 ||
      CopyBuffer(symbol.emaSlowHandle, 0, 0, 2, emaSlowBuffer) <= 0) {
      return false;
   }
   
   double currentFastEMA = emaFastBuffer[0];
   double previousFastEMA = emaFastBuffer[1];
   double currentSlowEMA = emaSlowBuffer[0];
   double previousSlowEMA = emaSlowBuffer[1];
   
   if(isLong) {
      return previousFastEMA > previousSlowEMA && currentFastEMA <= currentSlowEMA;
   } else {
      return previousFastEMA < previousSlowEMA && currentFastEMA >= currentSlowEMA;
   }
}

//+------------------------------------------------------------------+
//| Check if signal is confirmed by candle close                       |
//+------------------------------------------------------------------+
bool CheckSignalConfirmation(SymbolData &symbol, bool isLong) {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   if(CopyRates(symbol.symbol, PERIOD_H1, 0, 1, rates) <= 0) {
      return false;
   }
   
   if(isLong) {
      return rates[0].close > symbol.crossoverPrice;
   } else {
      return rates[0].close < symbol.crossoverPrice;
   }
}

//+------------------------------------------------------------------+
//| Check if H4 trend aligns with H1 signal                           |
//+------------------------------------------------------------------+
bool CheckH4TrendAlignment(SymbolData &symbol, bool isLong) {
   double emaFastH4Buffer[], emaSlowH4Buffer[];
   ArraySetAsSeries(emaFastH4Buffer, true);
   ArraySetAsSeries(emaSlowH4Buffer, true);
   
   if(CopyBuffer(symbol.emaFastH4Handle, 0, 0, 1, emaFastH4Buffer) <= 0 ||
      CopyBuffer(symbol.emaSlowH4Handle, 0, 0, 1, emaSlowH4Buffer) <= 0) {
      return false;
   }
   
   double currentFastEMAH4 = emaFastH4Buffer[0];
   double currentSlowEMAH4 = emaSlowH4Buffer[0];
   
   if(ShowTradeLogs) {
      PrintFormat("[%s] H4 Trend - FastEMA: %.5f, SlowEMA: %.5f", 
                 symbol.symbol, currentFastEMAH4, currentSlowEMAH4);
   }
   
   if(isLong) {
      return currentFastEMAH4 > currentSlowEMAH4;
   } else {
      return currentFastEMAH4 < currentSlowEMAH4;
   }
}

//+------------------------------------------------------------------+
//| Check volume confirmation using Volume Oscillator                  |
//+------------------------------------------------------------------+
bool CheckVolumeConfirmation(SymbolData &symbol, bool isLong) {
   double volOscBuffer[];
   ArraySetAsSeries(volOscBuffer, true);
   
   if(CopyBuffer(symbol.volOscHandle, 0, 0, 2, volOscBuffer) <= 0) {
      return false;
   }
   
   double currentVolOsc = volOscBuffer[0];
   double previousVolOsc = volOscBuffer[1];
   
   if(ShowTradeLogs) {
      PrintFormat("[%s] Volume Oscillator - Current: %.2f, Previous: %.2f", 
                 symbol.symbol, currentVolOsc, previousVolOsc);
   }
   
   if(isLong) {
      return currentVolOsc > previousVolOsc && currentVolOsc > VolOscThreshold;
   } else {
      return currentVolOsc < previousVolOsc && currentVolOsc < -VolOscThreshold;
   }
}

//+------------------------------------------------------------------+
//| Process a single symbol                                            |
//+------------------------------------------------------------------+
void ProcessSymbol(SymbolData &symbol) {
   // Vérifier et réinitialiser le compteur de trades quotidiens si nécessaire
   MqlDateTime currentDate;
   TimeToStruct(TimeCurrent(), currentDate);
   currentDate.hour = 0;
   currentDate.min = 0;
   currentDate.sec = 0;
   datetime today = StructToTime(currentDate);
   
   if(symbol.lastTradeDate < today) {
      symbol.dailyTradesCount = 0;
      symbol.lastTradeDate = today;
   }
   
   // Vérifier les annonces économiques
   if(IsNewsTime()) {
      if(ShowTradeLogs) {
         PrintFormat("[%s] Skipping trade due to news event", symbol.symbol);
      }
      return;
   }
   
   // Get current price and spread
   double currentBid = SymbolInfoDouble(symbol.symbol, SYMBOL_BID);
   double currentAsk = SymbolInfoDouble(symbol.symbol, SYMBOL_ASK);
   double currentSpread = currentAsk - currentBid;
   
   // Check spread
   if(currentSpread > MaxSpread * _Point) {
      return;
   }
   
   // Get indicator values
   double emaFastBuffer[], emaSlowBuffer[], adxBuffer[], volumeBuffer[], atrBuffer[];
   ArraySetAsSeries(emaFastBuffer, true);
   ArraySetAsSeries(emaSlowBuffer, true);
   ArraySetAsSeries(adxBuffer, true);
   ArraySetAsSeries(volumeBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   
   if(CopyBuffer(symbol.emaFastHandle, 0, 0, 2, emaFastBuffer) <= 0 ||
      CopyBuffer(symbol.emaSlowHandle, 0, 0, 2, emaSlowBuffer) <= 0 ||
      CopyBuffer(symbol.adxHandle, 0, 0, 2, adxBuffer) <= 0 ||
      CopyBuffer(symbol.volumeHandle, 0, 0, 2, volumeBuffer) <= 0 ||
      CopyBuffer(symbol.atrHandle, 0, 0, 1, atrBuffer) <= 0) {
      return;
   }
   
   double currentFastEMA = emaFastBuffer[0];
   double previousFastEMA = emaFastBuffer[1];
   double currentSlowEMA = emaSlowBuffer[0];
   double previousSlowEMA = emaSlowBuffer[1];
   double currentADX = adxBuffer[0];
   double currentVolume = volumeBuffer[0];
   double previousVolume = volumeBuffer[1];
   double currentATR = atrBuffer[0];
   
   // Log des valeurs
   if(ShowTradeLogs) {
      PrintFormat("[%s] H1 Indicators - FastEMA: %.5f, SlowEMA: %.5f, ADX: %.2f, Volume: %.0f, ATR: %.5f", 
                 symbol.symbol, currentFastEMA, currentSlowEMA, currentADX, currentVolume, currentATR);
   }
   
   // Check for EMA crosses
   bool emaCrossedUp = previousFastEMA <= previousSlowEMA && currentFastEMA > currentSlowEMA;
   bool emaCrossedDown = previousFastEMA >= previousSlowEMA && currentFastEMA < currentSlowEMA;
   
   // Store crossover signal if new
   if(emaCrossedUp || emaCrossedDown) {
      symbol.lastSignalTime = TimeCurrent();
      symbol.crossoverPrice = (currentBid + currentAsk) / 2;
      symbol.signalConfirmed = false;
      if(ShowTradeLogs) {
         PrintFormat("[%s] New EMA crossover signal at price: %.5f", symbol.symbol, symbol.crossoverPrice);
      }
   }
   
   // Check if we need to confirm the signal
   if(!symbol.signalConfirmed && symbol.lastSignalTime > 0) {
      symbol.signalConfirmed = CheckSignalConfirmation(symbol, emaCrossedUp);
      if(symbol.signalConfirmed && ShowTradeLogs) {
         PrintFormat("[%s] Signal confirmed by candle close", symbol.symbol);
      }
   }
   
   // Check ADX condition
   bool adxCondition = currentADX > ADXThreshold;
   
   // Check volume condition
   bool volumeCondition = currentVolume > previousVolume;
   
   // Check H4 trend alignment
   bool h4TrendAligned = CheckH4TrendAlignment(symbol, emaCrossedUp);
   
   // Check volume oscillator confirmation
   bool volOscConfirmed = CheckVolumeConfirmation(symbol, emaCrossedUp);
   
   // Check retracement condition
   bool retracementConfirmed = CheckRetracement(symbol, emaCrossedUp);
   
   // Find swing points for stop loss with ATR buffer
   double swingHigh = FindSwingHigh(symbol.symbol, SwingPeriods, currentATR);
   double swingLow = FindSwingLow(symbol.symbol, SwingPeriods, currentATR);
   
   // Calculate EMA 100 value
   double ema100Buffer[];
   ArraySetAsSeries(ema100Buffer, true);
   if(CopyBuffer(symbol.ema100Handle, 0, 0, 1, ema100Buffer) <= 0) {
      return;
   }
   
   double lastEMA100 = ema100Buffer[0];
   
   // Calculate EMA 200 value
   double ema200Buffer[];
   ArraySetAsSeries(ema200Buffer, true);
   if(CopyBuffer(symbol.ema200Handle, 0, 0, 1, ema200Buffer) <= 0) {
      return;
   }
   
   double lastEMA200 = ema200Buffer[0];
   
   // Determine bullish or bearish conditions using both EMAs
   bool isBullish = (currentBid > lastEMA100 && currentBid > lastEMA200);
   bool isBearish = (currentBid < lastEMA100 && currentBid < lastEMA200);
   
   // Log the market condition
   if(ShowTradeLogs) {
      if(isBullish) {
         PrintFormat("[%s] Market is Bullish", symbol.symbol);
      } else if(isBearish) {
         PrintFormat("[%s] Market is Bearish", symbol.symbol);
      } else {
         PrintFormat("[%s] Market is Neutral", symbol.symbol);
      }
   }
   
   // Modify buy conditions to include EMA 100
   if(TradeDirection != TRADE_SELL && emaCrossedUp && adxCondition && volumeCondition && 
      symbol.signalConfirmed && h4TrendAligned && volOscConfirmed && retracementConfirmed && isBullish) {
      if(symbol.dailyTradesCount < MaxDailyTrades) {
         // Calculate stop loss and take profit with ATR buffer
         double sl = swingLow;
         double tp = currentBid + (currentBid - sl) * RiskRewardRatio;
         
         // Get account balance and calculate position size based on risk
         double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         double riskAmount = accountBalance * RiskPercent / 100;
         double lotSize = riskAmount / ((currentBid - sl) * 10);
         
         // Normalize lot size to valid values
         double minLot = SymbolInfoDouble(symbol.symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(symbol.symbol, SYMBOL_VOLUME_MAX);
         double lotStep = SymbolInfoDouble(symbol.symbol, SYMBOL_VOLUME_STEP);
         
         lotSize = MathFloor(lotSize / lotStep) * lotStep;
         lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
         
         if(symbol.trade.Buy(lotSize, symbol.symbol, 0, sl, tp, "EMA Buy Signal")) {
            symbol.dailyTradesCount++;
            symbol.lastTradeDate = TimeCurrent();
            symbol.lastSignalTime = 0;  // Reset signal time after trade
            symbol.signalConfirmed = false;
            symbol.retracementConfirmed = false;
            if(ShowTradeLogs) {
               PrintFormat("[%s] Buy trade opened. Balance: %.2f, Risk: %.2f, Lot size: %.2f, SL: %.5f, TP: %.5f", 
                         symbol.symbol, accountBalance, riskAmount, lotSize, sl, tp);
            }
         }
      }
   }
   
   // Modify sell conditions to include EMA 100
   if(TradeDirection != TRADE_BUY && emaCrossedDown && adxCondition && volumeCondition && 
      symbol.signalConfirmed && h4TrendAligned && volOscConfirmed && retracementConfirmed && isBearish) {
      if(symbol.dailyTradesCount < MaxDailyTrades) {
         // Calculate stop loss and take profit with ATR buffer
         double sl = swingHigh;
         double tp = currentAsk - (sl - currentAsk) * RiskRewardRatio;
         
         // Get account balance and calculate position size based on risk
         double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         double riskAmount = accountBalance * RiskPercent / 100;
         double lotSize = riskAmount / ((sl - currentAsk) * 10);
         
         // Normalize lot size to valid values
         double minLot = SymbolInfoDouble(symbol.symbol, SYMBOL_VOLUME_MIN);
         double maxLot = SymbolInfoDouble(symbol.symbol, SYMBOL_VOLUME_MAX);
         double lotStep = SymbolInfoDouble(symbol.symbol, SYMBOL_VOLUME_STEP);
         
         lotSize = MathFloor(lotSize / lotStep) * lotStep;
         lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
         
         if(symbol.trade.Sell(lotSize, symbol.symbol, 0, sl, tp, "EMA Sell Signal")) {
            symbol.dailyTradesCount++;
            symbol.lastTradeDate = TimeCurrent();
            symbol.lastSignalTime = 0;  // Reset signal time after trade
            symbol.signalConfirmed = false;
            symbol.retracementConfirmed = false;
            if(ShowTradeLogs) {
               PrintFormat("[%s] Sell trade opened. Balance: %.2f, Risk: %.2f, Lot size: %.2f, SL: %.5f, TP: %.5f", 
                         symbol.symbol, accountBalance, riskAmount, lotSize, sl, tp);
            }
         }
      }
   }
   
   // Check for exit conditions on open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == symbol.symbol && PositionGetInteger(POSITION_MAGIC) == Magic) {
            bool isLong = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
            
            // Check EMA crossover exit condition
            if(ExitMethod == EXIT_EMA || ExitMethod == EXIT_BOTH) {
               if(ShouldExitOnEMACrossover(symbol, isLong)) {
                  symbol.trade.PositionClose(ticket);
                  if(ShowTradeLogs) {
                     PrintFormat("[%s] Position closed due to EMA crossover. Ticket: %d", symbol.symbol, ticket);
                  }
               }
            }
         }
      }
   }
} 