// Declaration of EA properties
#property copyright ""; // Copyright property (to be defined)
#property link "";      // Associated link to the EA (to be defined)
#property version "";   // Version of the EA (to be defined)
#property strict        // Enforces strict compiler rules

color Gray1 = clrSilver; // Use built-in color

// --- Fix: Declare missing variables and stubs ---
datetime time_start_buy = 0;
datetime time_start_sell = 0;
int SpeedEA = 1; // Default 1 second for EA speed, adjust as needed
bool Info = true;   // Default to true, set as needed

string error_message_buy = "";
string sell_order_symbol = "";
string sell_order_info = "";
string error_message_sell = "";
string buy_stop_order_log = "";
string sell_stop_order_log = "";

// Declaration of a function to return error descriptions
string ErrorDescription(int); // Returns a description based on the error code

// Enumeration for lot assignment methods (Fixed, Auto, Ratio)
enum LotAss
{
  Fixed = 0,       // Fixed lot assignment
  AutoMM = 1,      // Automatic Money Management (percentage risk)
  BalanceRatio = 2 // Balance-to-lot ratio
};

extern int MagicNumber = 54785; // Unique identifier for EA's trades

input string s3 = "------------ Strategy Settings ----------------"; // Section header for strategy settings

// External variables for user inputs
extern double FixedLots = 0.1;                                       // Fixed lot size
extern string PercentageRiskSettings = "***************************"; // Placeholder string for risk settings
extern double PercentageRisk = 0.1;                                   // Percentage of account balance to risk
extern int PercentageRiskBasedOnPointsMovement = 100;                 // Points movement for risk calculation
extern string BalanceRatioSettings = "***************************";   // Placeholder string for balance ratio settings
extern double ForEvery = 1000;                                        // Balance increment for lot calculation
extern double UseLotsForEveryBalance = 0.1;                          // Lot size for every balance increment
extern string LotsSelection = "***************************";          // Placeholder string for lot selection
extern LotAss LotAssignment = Fixed;                                  // Lot assignment method (Fixed by default)
input bool AutoTPTralBySymbol = true; // Enable automatic TP/Tral/TralStart adaptation by symbol
extern int TakeProfit = 30;                                           // Take profit in pips
extern double Tral = 20;                                              // Trailing stop in pips
extern double TralStart = 10;                                          // Start trailing when profit exceeds 5 pips

input string s4d = "------------ Stop Loss  ----------------"; // Section header for stop loss settings
input bool UseStopLoss = false;
input int StopLoss = 500;

extern double MaxSpread = 40; // Maximum spread allowed for trade execution
extern double PipsStep = 1;  // Pip step for trailing stop or entry
extern int OpenTime = 1;      // Time to keep trade open (in hours)

input string s4 = "------------ Options ----------------"; // Section header for options
input string trading_system_name;                          // Name or comment for the trading system
enum point_type
{
  point_type_point,
  point_type_pips,
};

input point_type PointType = point_type_point; // Choose between points or pips for calculations

input string s35d = "----------- RSI Filter ----------------"; // Section header for RSI filter
input bool UseRSIFilter = true; // Enable or disable RSI filter
input ENUM_TIMEFRAMES RSIFilter_TF = PERIOD_CURRENT; // Timeframe for RSI filter
input int Filter_RSI_Period = 14; // RSI period for filter
input double Filter_StopBuyAboveRSI = 30; // Do not buy if RSI is above this value
input double Filter_StopBuyBelow = 0;     // Do not buy if RSI is below this value
input double Filter_StopSellAboveRSI = 100; // Do not sell if RSI is above this value
input double Filter_StopSellBelow = 70;    // Do not sell if RSI is below this value

input string s5 = "------------ Trading Hours ----------------"; // Section header for trading hours
input int TimeStart_Hour = 0; // Trading start hour (0-23)
input int TimeStart_Minute = 0; // Trading start minute (0-59)
input int TimeEnd_Hour = 24;     // Trading end hour (0-23)
input int TimeEnd_Minute = 0;   // Trading end minute (0-59)

input string s13 = "------------ Max Orders      ----------------"; // Section header for max orders
input int MaxOrdersBuy = 30; // Maximum number of buy orders allowed
input int MaxOrdersSell = 30; // Maximum number of sell orders allowed

enum dir
{
  dir_both, // BUY&SELL
  dir_buy,  // ONLY BUY
  dir_sell  // ONLY SELL
};

input dir Direction = dir_both; // Trading direction: both, buy only, or sell only

enum tar
{
  tar_both, // BUY&SELL
  tar_only, // BUY OR SELL
};

input tar TakeProfitMode = tar_only; // Mode de gestion du profit : séparé (défaut) ou groupé

bool rsi_buy;
bool rsi_sell;

datetime TimeFlag = 1;

string str_symb_prop = "";
void On_Init()
{
  Print("ID " + IntegerToString(int(__DATETIME__)));
  str_symb_prop = SymbProperties();
  ChartSetInteger(0, CHART_SHOW_GRID, false);
}

// Internal variables for managing logic and flow
bool initialization_completed; // Flag to check if initialization is completed
int order_id;                  // Order identifier
string email_address;          // Email address for notifications
bool backtest_disabled;        // Backtesting flag
string status_message;         // Status message for logging
int execution_timer;           // Timer for controlling EA execution speed
double total_profit;           // Variable to store total profit
int order_total;               // Total number of orders
int order_counter;             // Counter for looping through orders

double order_profit;                 // Profit from individual orders
int loop_counter;                    // Loop counter for various processes
int closed_order_counter;            // Counter for closed orders
double current_total_profit;         // Variable for calculating total profit during loops
bool is_initialized;                 // Flag to check if the system is initialized
bool is_trading_paused;              // Flag to pause trading under certain conditions
double price_spread;                 // Current market spread
long last_execution_time;            // Time of the last trade execution
double current_bid_price;            // Current bid price of the asset
long trade_open_time;                // Open time of the trade
double max_loss;                     // Maximum loss tracked in a session
int current_order_index;             // Index of the current order being processed
int pending_order_count;             // Count of pending orders
double total_open_profit;            // Total open profit from all trades
double account_drawdown;             // Current drawdown of the account
int total_open_orders;               // Total number of open orders
int processed_order_count;           // Number of orders processed in a loop
int order_processing_counter;        // Counter for order processing
double calculated_lot_size;          // Lot size calculated based on account size and risk
double adjusted_lot_size;            // Adjusted lot size based on market conditions
int lots_calculation_index;          // Index for calculating lot sizes
double lot_calculation_result;       // Result of lot size calculation
double final_lot_size;               // Final lot size to be used for trade
int order_send_result;               // Result of order sending (success or failure)
int open_orders_counter;             // Counter for open orders
int total_order_list;                // Total number of orders in the list
int processed_order_list;            // Processed orders in the list
double fixed_lots_size;              // Size of fixed lots
double risk_amount;                  // Risk amount for percentage-based lot sizing
int percentage_risk_based_points;    // Points for calculating percentage risk
double lot_risk_calculation;         // Calculation of lot size based on risk
double minimum_lot_size;             // Minimum lot size allowed
int successful_trades_count;         // Count of successful trades
int orders_iteration_counter;        // Counter for iterating through orders
int pending_orders_index;            // Index for pending orders
long account_limit_orders;           // Limit on the number of orders per account
long active_orders_count;            // Number of currently active orders
int orders_limit_index;              // Index to check against the order limit
int pending_orders_processing;       // Pending orders in processing
int open_orders_iteration;           // Iteration counter for open orders
int open_orders_tracker;             // Tracker for open orders
long order_open_time_limit;          // Time limit for order open duration
int total_orders_today;              // Total number of orders placed today
int pending_orders_today;            // Pending orders for today
int today_orders_iteration;          // Iteration counter for today's orders
double fixed_profit;                 // Fixed profit for today
double adjusted_profit;              // Adjusted profit based on market conditions
int orders_today_counter;            // Counter for today's orders
double daily_profit;                 // Total daily profit
double profit_calculation;           // Calculation of profit
int orders_profit_calculation_index; // Index for profit calculation for orders
int orders_today_iteration;          // Iteration for today's orders
int total_orders_this_week;          // Total orders placed this week
double weekly_profit;                // Weekly profit tracking
double adjusted_weekly_profit;       // Adjusted weekly profit based on conditions
int weekly_orders_index;             // Index for weekly orders
double calculated_weekly_profit;     // Calculated profit for the week
double week_total_profit;            // Total weekly profit
double final_week_profit;            // Final profit for the week
int week_order_counter;              // Counter for weekly orders
int order_profit_processing;         // Profit processing for orders
double weekly_profit_calculation;    // Calculation of weekly profit
int total_orders_last_week;          // Total orders from last week
int last_week_orders_count;          // Count of orders from last week
double calculated_last_week_profit;  // Calculated profit for last week
int last_week_order_counter;         // Counter for last week's orders
int weekly_order_processing;         // Processing orders for the week
int successful_week_orders;          // Count of successful weekly orders
int week_order_tracker;              // Tracker for weekly orders
int total_orders_this_month;         // Total orders placed this month
int monthly_orders_index;            // Index for monthly orders
int monthly_orders_counter;          // Counter for monthly orders
int orders_this_month_processing;    // Processing orders for the month
double monthly_profit;               // Total monthly profit
int monthly_orders_profit;           // Profit from orders this month
int open_monthly_orders;             // Open orders for the month
double monthly_profit_calculation;   // Calculation of monthly profit
double monthly_total_profit;         // Total monthly profit
int monthly_order_tracker;           // Tracker for monthly orders
int monthly_open_orders;             // Open orders for the month
double final_monthly_profit;         // Final monthly profit
double monthly_drawdown;             // Monthly drawdown amount
int orders_processed_this_month;     // Orders processed this month
int monthly_order_processing;        // Processing monthly orders
long month_orders_open_time;         // Time orders were open during the month
double total_monthly_profit;         // Total profit for the month
double final_month_total_profit;     // Final total profit for the month
int total_yearly_orders;             // Total orders for the year
int yearly_orders_counter;           // Counter for yearly orders
long yearly_orders_open_time;        // Open time for yearly orders
double total_year_profit;            // Total profit for the year
double final_yearly_profit;          // Final yearly profit
int yearly_order_counter;            // Counter for yearly orders
int orders_processed_this_year;      // Orders processed for the year
long yearly_orders_timestamp;        // Timestamp for yearly orders
double year_profit;                  // Profit for the year
double adjusted_year_profit;         // Adjusted yearly profit
int successful_year_orders;          // Count of successful yearly orders
int yearly_profit_tracker;           // Tracker for yearly profit
long year_open_timestamp;            // Timestamp for year opening
double final_year_profit;            // Final profit for the year
long next_trading_time;              // Time for the next trade
double current_drawdown;             // Current account drawdown
int drawdown_timer;                  // Timer for managing drawdown pauses
bool is_trading_active;              // Flag for active trading status
int information_font_size;           // Font size for displayed information
int order_speed;                     // Speed of order execution
double current_profit_value;         // Current profit value
double returned_double;              // Return value for calculations
bool order_check;                    // Flag to check if an order is valid

// === Variables globales pour trailing global par sens ===
double max_profit_buy = 0;
double max_profit_sell = 0;


///////////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////////

// Initialization function that is called once when the EA is loaded
int init()
{
  SetTP_SL_BySymbol(); // Set TP/Tral/TralStart automatically if enabled
  time_start_buy = 1;
  time_start_sell = 1;
  On_Init();
  // Initialize key variables
  int closed_orders_counter;                // Counter for closed orders
  initialization_completed = true;          // Mark initialization as completed
  order_id = 18120;                         // Assign order ID
  email_address = "hadrygassama@gmail.com"; // Set the email address for notifications
  backtest_disabled = true;                 // Disable backtesting for live environment
  status_message = "Backtest Disabled";     // Set status message
  is_trading_paused = false;                // Start trading as not paused
  next_trading_time = 0;                    // Reset next trading time
                                            // trading_system_name = "Gold Scalper"; // Set the name of the trading system
  execution_timer = 0;                      // Initialize execution timer
  order_send_result = 0;                    // Initialize order sending result
  current_bid_price = 0;                    // Initialize bid price
  last_execution_time = 0;                  // Reset last execution time
  current_drawdown = 0;                     // Reset current drawdown
  price_spread = 0;                         // Initialize price spread
  account_drawdown = 0;                     // Initialize account drawdown
  is_initialized = false;                   // Mark the system as not initialized yet
  drawdown_timer = 0;                       // Initialize drawdown timer
  is_trading_active = true;                 // Mark trading as active
  information_font_size = 7;                // Set font size for info
  order_speed = 0;                          // Initialize order speed
                                            // Set a timer for EA execution speed control
  EventSetMillisecondTimer(SpeedEA);        // Timer to control EA speed
  execution_timer = 1;                      // Start execution timer
                                            // Ensure proper tick digits (for compatibility with broker data)
  if (_Digits != 5)                         // If broker uses less than 5 digits
  {
    if (_Digits != 3)
      return 0; // Check if it's not 3-digit, exit if invalid
  }
  execution_timer = 10;         // Set execution timer delay
  closed_orders_counter = 0;    // Initialize closed orders counter
  return closed_orders_counter; // Return closed orders count (initially zero)
}

// Function called on every tick (market price update)
void OnTick()
{
  Tick();
  double MyPoint = GetMyPoint();
  double profit = SummProfit(MagicNumber, OP_BUY) + SummProfit(MagicNumber, OP_SELL) + SummProfitDay(MagicNumber, OP_BUY) + SummProfitDay(MagicNumber, OP_SELL);
 
  // Variables for managing trade status and logging
  bool buy_signal;               // Flag to indicate buy signal
  bool SIGNAL_BUY;               // Flag to indicate sell signal
  bool take_profit_signal;       // Flag for take-profit signal
  bool SIGNAL_SELL;              // Flag for stop-loss signal
  double trailing_stop_distance; // Distance for trailing stop calculation
                                 // Logic for handling buy, sell, take profit, and stop loss signals
  if (is_initialized)
  {
    if (IsDemo() != true)
      return;
  }
  if (is_trading_paused != true)
  {
    current_total_profit = (Ask - Bid);
    price_spread = (current_total_profit / MyPoint);
    buy_signal = false;
    SIGNAL_BUY = false;
    take_profit_signal = false;
    SIGNAL_SELL = false;
    if (last_execution_time == 0)
    {
      last_execution_time = TimeCurrent();
    }
    if ((current_bid_price == 0))
    {
      current_bid_price = Bid;
    }
    trade_open_time = OpenTime;
    trade_open_time = last_execution_time + trade_open_time;
    if (trade_open_time < TimeCurrent())
    {
      last_execution_time = TimeCurrent();
      current_bid_price = Bid;
    }
    trade_open_time = OpenTime;
    trade_open_time = last_execution_time + trade_open_time;
    if (trade_open_time >= TimeCurrent())
    {
      current_total_profit = (PipsStep * MyPoint);
      if (((Bid - current_total_profit) >= current_bid_price))
      {
        buy_signal = true;
      }
    }
    trade_open_time = OpenTime;
    trade_open_time = last_execution_time + trade_open_time;
    if (trade_open_time >= TimeCurrent() && (((PipsStep * MyPoint) + Bid) <= current_bid_price))
    {
      take_profit_signal = true;
    }
    if (TradingTime())
    {
      if (MaxSpread == 0 || (MaxSpread >= price_spread))
      {
        if (buy_signal && TimeCurrent() > time_start_buy)
        {
          SIGNAL_BUY = true;
        }
      }
      if (MaxSpread == 0 || (MaxSpread >= price_spread))
      {
        if (take_profit_signal && TimeCurrent() > time_start_sell)
        {
          SIGNAL_SELL = true;
        }
      }
    }
    /////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////
    if (TimeFlag < iTime(Symbol(), 0, 1))
    {
      TimeFlag = iTime(Symbol(), 0, 1);
      rsi_buy = true;
      rsi_sell = true;
      if (UseRSIFilter)
      {
        double rsi_1 = iRSI(NULL, RSIFilter_TF, Filter_RSI_Period, PRICE_CLOSE, 1);
        if (rsi_1 > Filter_StopBuyAboveRSI)
          rsi_buy = false;
        if (rsi_1 < Filter_StopBuyBelow)
          rsi_buy = false;
        if (rsi_1 < Filter_StopSellBelow)
          rsi_sell = false;
        if (rsi_1 > Filter_StopSellAboveRSI)
          rsi_sell = false;
      }
    }
    ////////////////////////////////////////
    if (!(rsi_buy))
    {
      SIGNAL_BUY = false;
    }
    if (!(rsi_sell))
    {
      SIGNAL_SELL = false;
    }
    //---
    //+------------------------------------------------------------------+
    //|                                                                  |
    //+------------------------------------------------------------------+
    loop_counter = -1;
    max_loss = 0;
    current_order_index = OrdersTotal() - 1;
    pending_order_count = current_order_index;
    if (current_order_index >= 0)
    {
      do
      {
        if (OrderSelect(pending_order_count, 0, 0) && _Symbol == OrderSymbol() && OrderMagicNumber() == MagicNumber)
        {
          if (OrderType() == loop_counter || loop_counter == -1)
          {
            total_open_profit = OrderProfit();
            total_open_profit = (total_open_profit + OrderSwap());
            max_loss = ((total_open_profit + OrderCommission()) + max_loss);
          }
        }
        pending_order_count = pending_order_count - 1;
      } while (pending_order_count >= 0);
    }
    account_drawdown = (max_loss / (AccountBalance() / 100));
    current_order_index = -1;
    total_open_orders = 0;
    processed_order_count = OrdersTotal() - 1;
    order_processing_counter = processed_order_count;
    if (processed_order_count >= 0)
    {
      do
      {
        if (OrderSelect(order_processing_counter, 0, 0) && _Symbol == OrderSymbol() && MagicNumber == OrderMagicNumber())
        {
          if (current_order_index == -1 || OrderType() == current_order_index)
          {
            total_open_orders = total_open_orders + 1;
          }
        }
        order_processing_counter = order_processing_counter - 1;
      } while (order_processing_counter >= 0);
    }
    // Logic for managing lot sizes and executing buy or sell orders
    if (T_Count(OP_SELL, MagicNumber) == 0 && SIGNAL_SELL && (Direction == dir_both || Direction == dir_sell))
    {
      error_message_buy = _Symbol;
      calculated_lot_size = FixedLots;
      if (LotAssignment == 1)
      {
        adjusted_lot_size = (PercentageRisk * AccountBalance());
        lots_calculation_index = PercentageRiskBasedOnPointsMovement * 100;
        lot_calculation_result = (adjusted_lot_size / (lots_calculation_index * MarketInfo(error_message_buy, MODE_TICKVALUE)));
        calculated_lot_size = lot_calculation_result;
        if ((lot_calculation_result < MarketInfo(error_message_buy, MODE_MINLOT)))
        {
          calculated_lot_size = MarketInfo(error_message_buy, MODE_MINLOT);
        }
      }
      if (LotAssignment == 2)
      {
        lot_calculation_result = floor((AccountBalance() / ForEvery));
        calculated_lot_size = (lot_calculation_result * UseLotsForEveryBalance);
      }
      lot_calculation_result = floor((calculated_lot_size / MarketInfo(error_message_buy, MODE_MINLOT)));
      lot_calculation_result = (lot_calculation_result * MarketInfo(error_message_buy, MODE_MINLOT));
      calculated_lot_size = lot_calculation_result;
      returned_double = MarketInfo(error_message_buy, MODE_MINLOT);
      final_lot_size = lot_calculation_result;
      if (lot_calculation_result <= returned_double)
      {
        lot_calculation_result = returned_double;
      }
      else
      {
        lot_calculation_result = final_lot_size;
      }
      calculated_lot_size = lot_calculation_result;
      returned_double = MarketInfo(error_message_buy, MODE_MAXLOT);
      final_lot_size = lot_calculation_result;
      if (lot_calculation_result >= returned_double)
      {
        lot_calculation_result = returned_double;
      }
      else
      {
        lot_calculation_result = final_lot_size;
      }
      calculated_lot_size = lot_calculation_result;
      double sl = 0.0;
      if (UseStopLoss)
        sl = NormalizeDouble(Bid + StopLoss * MyPoint, _Digits);
      order_send_result = OrderSend(_Symbol, 1, lot_calculation_result, Bid, 5, sl, 0, trading_system_name, MagicNumber, 0, 255);
    }
    lots_calculation_index = -1;
    open_orders_counter = 0;
    total_order_list = OrdersTotal() - 1;
    processed_order_list = total_order_list;
    if (total_order_list >= 0)
    {
      do
      {
        if (OrderSelect(processed_order_list, 0, 0) && _Symbol == OrderSymbol() && MagicNumber == OrderMagicNumber())
        {
          if (lots_calculation_index == -1 || OrderType() == lots_calculation_index)
          {
            open_orders_counter = open_orders_counter + 1;
          }
        }
        processed_order_list = processed_order_list - 1;
      } while (processed_order_list >= 0);
    }
    if (T_Count(OP_BUY, MagicNumber) == 0 && SIGNAL_BUY && (Direction == dir_both || Direction == dir_buy))
    {
      sell_order_symbol = _Symbol;
      fixed_lots_size = FixedLots;
      if (LotAssignment == 1)
      {
        risk_amount = (PercentageRisk * AccountBalance());
        percentage_risk_based_points = PercentageRiskBasedOnPointsMovement * 100;
        lot_risk_calculation = (risk_amount / (percentage_risk_based_points * MarketInfo(sell_order_symbol, MODE_TICKVALUE)));
        fixed_lots_size = lot_risk_calculation;
        if ((lot_risk_calculation < MarketInfo(sell_order_symbol, MODE_MINLOT)))
        {
          fixed_lots_size = MarketInfo(sell_order_symbol, MODE_MINLOT);
        }
      }
      if (LotAssignment == 2)
      {
        lot_risk_calculation = floor((AccountBalance() / ForEvery));
        fixed_lots_size = (lot_risk_calculation * UseLotsForEveryBalance);
      }
      lot_risk_calculation = floor((fixed_lots_size / MarketInfo(sell_order_symbol, MODE_MINLOT)));
      lot_risk_calculation = (lot_risk_calculation * MarketInfo(sell_order_symbol, MODE_MINLOT));
      fixed_lots_size = lot_risk_calculation;
      returned_double = MarketInfo(sell_order_symbol, MODE_MINLOT);
      minimum_lot_size = lot_risk_calculation;
      if (lot_risk_calculation <= returned_double)
      {
        lot_risk_calculation = returned_double;
      }
      else
      {
        lot_risk_calculation = minimum_lot_size;
      }
      fixed_lots_size = lot_risk_calculation;
      returned_double = MarketInfo(sell_order_symbol, MODE_MAXLOT);
      minimum_lot_size = lot_risk_calculation;
      if (lot_risk_calculation >= returned_double)
      {
        lot_risk_calculation = returned_double;
      }
      else
      {
        lot_risk_calculation = minimum_lot_size;
      }
      fixed_lots_size = lot_risk_calculation;
      double sl = 0.0;
      if (UseStopLoss)
        sl = NormalizeDouble(Ask - StopLoss * MyPoint, _Digits);
      order_send_result = OrderSend(_Symbol, 0, lot_risk_calculation, Ask, 5, sl, 0, trading_system_name, MagicNumber, 0, 32768);
    }
    percentage_risk_based_points = -1;
    successful_trades_count = 0;
    orders_iteration_counter = OrdersTotal() - 1;
    pending_orders_index = orders_iteration_counter;
    if (orders_iteration_counter >= 0)
    {
      do
      {
        if (OrderSelect(pending_orders_index, 0, 0) && OrderMagicNumber() == MagicNumber)
        {
          if (percentage_risk_based_points == -1 || OrderType() == percentage_risk_based_points)
          {
            successful_trades_count = successful_trades_count + 1;
          }
        }
        pending_orders_index = pending_orders_index - 1;
      } while (pending_orders_index >= 0);
    }
    account_limit_orders = AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
    active_orders_count = successful_trades_count;
    if (active_orders_count < account_limit_orders || AccountInfoInteger(ACCOUNT_LIMIT_ORDERS) == 0)
    {
      orders_limit_index = -1;
      pending_orders_processing = 0;
      open_orders_iteration = OrdersTotal() - 1;
      open_orders_tracker = open_orders_iteration;
      if (open_orders_iteration >= 0)
      {
        do
        {
          if (OrderSelect(open_orders_tracker, 0, 0) && _Symbol == OrderSymbol() && OrderMagicNumber() == MagicNumber)
          {
            order_open_time_limit = OrderOpenTime();
            if (order_open_time_limit >= iTime(_Symbol, 0, 0))
            {
              if (orders_limit_index == -1 || OrderType() == orders_limit_index)
              {
                pending_orders_processing = pending_orders_processing + 1;
              }
            }
          }
          open_orders_tracker = open_orders_tracker - 1;
        } while (open_orders_tracker >= 0);
      }
      if (pending_orders_processing == 0)
      {
        open_orders_iteration = 0;
        total_orders_today = 0;
        pending_orders_today = OrdersTotal() - 1;
        today_orders_iteration = pending_orders_today;
        if (pending_orders_today >= 0)
        {
          do
          {
            if (OrderSelect(today_orders_iteration, 0, 0) && _Symbol == OrderSymbol() && MagicNumber == OrderMagicNumber())
            {
              if (open_orders_iteration == -1 || OrderType() == open_orders_iteration)
              {
                total_orders_today = total_orders_today + 1;
              }
            }
            today_orders_iteration = today_orders_iteration - 1;
          } while (today_orders_iteration >= 0);
        }
        if (T_Count(OP_BUY, MagicNumber) > 0 && T_Count(OP_BUY, MagicNumber) < MaxOrdersBuy && SIGNAL_BUY && (Direction == dir_both || Direction == dir_buy))
        {
          sell_order_info = _Symbol;
          fixed_profit = FixedLots;
          if (LotAssignment == 1)
          {
            adjusted_profit = (PercentageRisk * AccountBalance());
            orders_today_counter = PercentageRiskBasedOnPointsMovement * 100;
            daily_profit = (adjusted_profit / (orders_today_counter * MarketInfo(sell_order_info, MODE_TICKVALUE)));
            fixed_profit = daily_profit;
            if ((daily_profit < MarketInfo(sell_order_info, MODE_MINLOT)))
            {
              fixed_profit = MarketInfo(sell_order_info, MODE_MINLOT);
            }
          }
          if (LotAssignment == 2)
          {
            daily_profit = floor((AccountBalance() / ForEvery));
            fixed_profit = (daily_profit * UseLotsForEveryBalance);
          }
          daily_profit = floor((fixed_profit / MarketInfo(sell_order_info, MODE_MINLOT)));
          daily_profit = (daily_profit * MarketInfo(sell_order_info, MODE_MINLOT));
          fixed_profit = daily_profit;
          returned_double = MarketInfo(sell_order_info, MODE_MINLOT);
          profit_calculation = daily_profit;
          if (daily_profit <= returned_double)
          {
            daily_profit = returned_double;
          }
          else
          {
            daily_profit = profit_calculation;
          }
          fixed_profit = daily_profit;
          returned_double = MarketInfo(sell_order_info, MODE_MAXLOT);
          profit_calculation = daily_profit;
          if (daily_profit >= returned_double)
          {
            daily_profit = returned_double;
          }
          else
          {
            daily_profit = profit_calculation;
          }
          fixed_profit = daily_profit;
          double sl = 0.0;
          if (UseStopLoss)
            sl = NormalizeDouble(Ask - StopLoss * MyPoint, _Digits);
          order_send_result = OrderSend(_Symbol, 0, daily_profit, Ask, 10, sl, 0, trading_system_name, MagicNumber, 0, 32768);
        }
        orders_today_counter = 1;
        orders_profit_calculation_index = 0;
        orders_today_iteration = OrdersTotal() - 1;
        total_orders_this_week = orders_today_iteration;
        if (orders_today_iteration >= 0)
        {
          do
          {
            if (OrderSelect(total_orders_this_week, 0, 0) && _Symbol == OrderSymbol() && MagicNumber == OrderMagicNumber())
            {
              if (orders_today_counter == -1 || OrderType() == orders_today_counter)
              {
                orders_profit_calculation_index = orders_profit_calculation_index + 1;
              }
            }
            total_orders_this_week = total_orders_this_week - 1;
          } while (total_orders_this_week >= 0);
        }
        if (T_Count(OP_SELL, MagicNumber) > 0 && T_Count(OP_SELL, MagicNumber) < MaxOrdersSell && SIGNAL_SELL && (Direction == dir_both || Direction == dir_sell))
        {
          error_message_sell = _Symbol;
          weekly_profit = FixedLots;
          if (LotAssignment == 1)
          {
            adjusted_weekly_profit = (PercentageRisk * AccountBalance());
            weekly_orders_index = PercentageRiskBasedOnPointsMovement * 100;
            calculated_weekly_profit = (adjusted_weekly_profit / (weekly_orders_index * MarketInfo(error_message_sell, MODE_TICKVALUE)));
            weekly_profit = calculated_weekly_profit;
            if ((calculated_weekly_profit < MarketInfo(error_message_sell, MODE_MINLOT)))
            {
              weekly_profit = MarketInfo(error_message_sell, MODE_MINLOT);
            }
          }
          if (LotAssignment == 2)
          {
            calculated_weekly_profit = floor((AccountBalance() / ForEvery));
            weekly_profit = (calculated_weekly_profit * UseLotsForEveryBalance);
          }
          calculated_weekly_profit = floor((weekly_profit / MarketInfo(error_message_sell, MODE_MINLOT)));
          calculated_weekly_profit = (calculated_weekly_profit * MarketInfo(error_message_sell, MODE_MINLOT));
          weekly_profit = calculated_weekly_profit;
          returned_double = MarketInfo(error_message_sell, MODE_MINLOT);
          week_total_profit = calculated_weekly_profit;
          if (calculated_weekly_profit <= returned_double)
          {
            calculated_weekly_profit = returned_double;
          }
          else
          {
            calculated_weekly_profit = week_total_profit;
          }
          weekly_profit = calculated_weekly_profit;
          returned_double = MarketInfo(error_message_sell, MODE_MAXLOT);
          week_total_profit = calculated_weekly_profit;
          if (calculated_weekly_profit >= returned_double)
          {
            calculated_weekly_profit = returned_double;
          }
          else
          {
            calculated_weekly_profit = week_total_profit;
          }
          weekly_profit = calculated_weekly_profit;
          double sl = 0.0;
          if (UseStopLoss)
            sl = NormalizeDouble(Bid + StopLoss * MyPoint, _Digits);
          order_send_result = OrderSend(_Symbol, 1, calculated_weekly_profit, Bid, 10, sl, 0, trading_system_name, MagicNumber, 0, 255);
        }
      }
    }
    weekly_orders_index = -1;
    final_week_profit = 0;
    week_order_counter = OrdersTotal() - 1;
    order_profit_processing = week_order_counter;
    if (week_order_counter >= 0)
    {
      do
      {
        if (OrderSelect(order_profit_processing, 0, 0) && OrderMagicNumber() == MagicNumber)
        {
          if (OrderType() == weekly_orders_index || weekly_orders_index == -1)
          {
            final_week_profit = (final_week_profit + OrderLots());
          }
        }
        order_profit_processing = order_profit_processing - 1;
      } while (order_profit_processing >= 0);
    }
    trailing_stop_distance = (final_week_profit * TakeProfit);
    week_order_counter = -1;
    weekly_profit_calculation = 0;
    total_orders_last_week = OrdersTotal() - 1;
    last_week_orders_count = total_orders_last_week;
    if (total_orders_last_week >= 0)
    {
      do
      {
        if (OrderSelect(last_week_orders_count, 0, 0) && OrderMagicNumber() == MagicNumber)
        {
          if (OrderType() == week_order_counter || week_order_counter == -1)
          {
            calculated_last_week_profit = OrderProfit();
            calculated_last_week_profit = (calculated_last_week_profit + OrderSwap());
            weekly_profit_calculation = ((calculated_last_week_profit + OrderCommission()) + weekly_profit_calculation);
          }
        }
        last_week_orders_count = last_week_orders_count - 1;
      } while (last_week_orders_count >= 0);
    }
    if ((weekly_profit_calculation >= trailing_stop_distance) && (trailing_stop_distance != 0))
    {
      total_orders_last_week = -1;
      last_week_order_counter = 0;
      weekly_order_processing = OrdersTotal() - 1;
      successful_week_orders = weekly_order_processing;
      if (weekly_order_processing >= 0)
      {
        do
        {
          if (OrderSelect(successful_week_orders, 0, 0) && _Symbol == OrderSymbol() && MagicNumber == OrderMagicNumber())
          {
            if (total_orders_last_week == -1 || OrderType() == total_orders_last_week)
            {
              last_week_order_counter = last_week_order_counter + 1;
            }
          }
          successful_week_orders = successful_week_orders - 1;
        } while (successful_week_orders >= 0);
      }
      if (last_week_order_counter > 1)
      {
        weekly_order_processing = OrdersTotal() - 1;
        week_order_tracker = weekly_order_processing;
        if (weekly_order_processing >= 0)
        {
          do
          {
            if (OrderSelect(week_order_tracker, 0, 0) && OrderMagicNumber() == MagicNumber)
            {
              if (OrderType() == OP_BUY)
              {
                RefreshRates();
                buy_stop_order_log = OrderSymbol();
                order_check = OrderClose(OrderTicket(), OrderLots(), NormalizeDouble(MarketInfo(buy_stop_order_log, MODE_BID), _Digits), 10, 16777215);
              }
              if (OrderType() == OP_SELL)
              {
                RefreshRates();
                sell_stop_order_log = OrderSymbol();
                order_check = OrderClose(OrderTicket(), OrderLots(), NormalizeDouble(MarketInfo(sell_stop_order_log, MODE_ASK), _Digits), 10, 16777215);
              }
            }
            week_order_tracker = week_order_tracker - 1;
          } while (week_order_tracker >= 0);
        }
      }
    }
    total_orders_this_month = -1;
    monthly_orders_index = 0;
    monthly_orders_counter = OrdersTotal() - 1;
    orders_this_month_processing = monthly_orders_counter;
    if (monthly_orders_counter >= 0)
    {
      do
      {
        if (OrderSelect(orders_this_month_processing, 0, 0) && _Symbol == OrderSymbol() && MagicNumber == OrderMagicNumber())
        {
          if (total_orders_this_month == -1 || OrderType() == total_orders_this_month)
          {
            monthly_orders_index = monthly_orders_index + 1;
          }
        }
        orders_this_month_processing = orders_this_month_processing - 1;
      } while (orders_this_month_processing >= 0);
    }
    if (monthly_orders_index == 1)
    {
      func_ApplyTrailingStop();
    }
    if (Info == false)
      return;
  }
  if (iTime(NULL, 1440, 0) <= next_trading_time)
    return;

  // === TP et Trailing global séparés ===
  double profit_buy = SummProfit(MagicNumber, OP_BUY);
  double profit_sell = SummProfit(MagicNumber, OP_SELL);

  if (TakeProfitMode == tar_both) {
      double profit_total = profit_buy + profit_sell;
      // --- TP groupe BUY+SELL ---
      if (profit_total >= TakeProfit && profit_total > 0) {
          CloseAllBuy(MagicNumber);
          CloseAllSell(MagicNumber);
          max_profit_buy = 0;
          max_profit_sell = 0;
      }
      // --- Trailing groupe BUY+SELL ---
      static double max_profit_total = 0;
      if (profit_total > max_profit_total) max_profit_total = profit_total;
      if (max_profit_total > TralStart && (max_profit_total - profit_total) >= Tral && profit_total > 0) {
          CloseAllBuy(MagicNumber);
          CloseAllSell(MagicNumber);
          max_profit_total = 0;
          max_profit_buy = 0;
          max_profit_sell = 0;
      }
  } else {
      // --- TP groupe BUY ---
      if (profit_buy >= TakeProfit && profit_buy > 0) {
          CloseAllBuy(MagicNumber);
          max_profit_buy = 0;
      }
      // --- TP groupe SELL ---
      if (profit_sell >= TakeProfit && profit_sell > 0) {
          CloseAllSell(MagicNumber);
          max_profit_sell = 0;
      }
      // --- Trailing groupe BUY ---
      if (profit_buy > max_profit_buy) max_profit_buy = profit_buy;
      if (max_profit_buy > TralStart && (max_profit_buy - profit_buy) >= Tral && profit_buy > 0) {
          CloseAllBuy(MagicNumber);
          max_profit_buy = 0;
      }
      // --- Trailing groupe SELL ---
      if (profit_sell > max_profit_sell) max_profit_sell = profit_sell;
      if (max_profit_sell > TralStart && (max_profit_sell - profit_sell) >= Tral && profit_sell > 0) {
          CloseAllSell(MagicNumber);
          max_profit_sell = 0;
      }
  }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Tick()
{
  double average_buy = AveragePrice(MagicNumber, OP_BUY);
  double average_sell = AveragePrice(MagicNumber, OP_SELL);
  ChartTrendLine("average_buy", iTime(NULL, 0, 100), average_buy, iTime(NULL, 0, 0) + 100 * PeriodSeconds(), average_buy, 2, clrBlue);
  ChartTrendLine("average_sell", iTime(NULL, 0, 100), average_sell, iTime(NULL, 0, 0) + 100 * PeriodSeconds(), average_sell, 2, clrRed);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  EventKillTimer();
  ObjectsDeleteAll(0, 23);
  ObjectsDeleteAll(0, 28);
  ObjectsDeleteAll(0, "ma_filter");
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
  RefreshRates();
  OnTick();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void func_ApplyTrailingStop()
{
  double MyPoint = GetMyPoint();
  int closed_orders_counter;
  double trailing_stop_distance;
  double current_stop_loss;
  bool stop_loss_modified_success;
  int order_iteration_index;
  closed_orders_counter = 0;
  trailing_stop_distance = 0;
  current_stop_loss = 0;
  stop_loss_modified_success = false;
  order_iteration_index = OrdersTotal() - 1;
  if (order_iteration_index < 0)
    return;
  do
  {
    if (OrderSelect(order_iteration_index, 0, 0) && OrderSymbol() == _Symbol && OrderMagicNumber() == MagicNumber)
    {
      closed_orders_counter = OrderTicket();
      trailing_stop_distance = OrderOpenPrice();
      current_stop_loss = OrderStopLoss();
      if (OrderType() == OP_BUY && (Tral != 0))
      {
        if ((current_stop_loss < trailing_stop_distance) || (current_stop_loss == 0))
        {
          total_profit = ((Tral + TralStart) * MyPoint);
          if (((Bid - total_profit) >= trailing_stop_distance))
          {
            stop_loss_modified_success = OrderModify(closed_orders_counter, OrderOpenPrice(), ((TralStart * MyPoint) + trailing_stop_distance), OrderTakeProfit(), 0, 4294967295);
          }
        }
        if ((current_stop_loss >= trailing_stop_distance))
        {
          order_profit = (Tral * MyPoint);
          if (((Bid - order_profit) > current_stop_loss))
          {
            current_profit_value = (Tral * MyPoint);
            stop_loss_modified_success = OrderModify(closed_orders_counter, OrderOpenPrice(), (Bid - current_profit_value), OrderTakeProfit(), 0, 4294967295);
          }
        }
      }
      if (OrderType() == OP_SELL && (Tral != 0))
      {
        if (current_stop_loss > trailing_stop_distance || (current_stop_loss == 0))
        {
          if (((((Tral + TralStart) * MyPoint) + Ask) <= trailing_stop_distance))
          {
            current_total_profit = (TralStart * MyPoint);
            stop_loss_modified_success = OrderModify(closed_orders_counter, OrderOpenPrice(), (trailing_stop_distance - current_total_profit), OrderTakeProfit(), 0, 4294967295);
          }
        }
        if ((current_stop_loss <= trailing_stop_distance) && (((Tral * MyPoint) + Ask) < current_stop_loss))
        {
          stop_loss_modified_success = OrderModify(closed_orders_counter, OrderOpenPrice(), ((Tral * MyPoint) + Ask), OrderTakeProfit(), 0, 4294967295);
        }
      }
    }
    order_iteration_index = order_iteration_index - 1;
  } while (order_iteration_index >= 0);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void func_CloseOrDeleteOrders(string close_reason)
{
  int closed_orders_counter;
  int order_list_index;
  closed_orders_counter = 0;
  order_list_index = OrdersTotal() - 1;
  if (order_list_index >= 0)
  {
    do
    {
      if (OrderSelect(order_list_index, 0, 0) && OrderMagicNumber() == MagicNumber && OrderSymbol() == _Symbol && OrderComment() == trading_system_name)
      {
        if (OrderType() == OP_BUY)
        {
          if (OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_BID), (int)MarketInfo(OrderSymbol(), MODE_SPREAD), 4294967295))
          {
            Print("Buy ticket ", OrderTicket(), " closed");
            closed_orders_counter = closed_orders_counter + 1;
          }
          else
          {
            Print("Cannot close buy ticket ", OrderTicket(), " error: ", ErrorDescription(GetLastError()));
          }
        }
        if (OrderType() == OP_SELL)
        {
          if (OrderClose(OrderTicket(), OrderLots(), MarketInfo(OrderSymbol(), MODE_ASK), (int)MarketInfo(OrderSymbol(), MODE_SPREAD), 4294967295))
          {
            Print("Sell ticket ", OrderTicket(), " closed");
            closed_orders_counter = closed_orders_counter + 1;
          }
          else
          {
            Print("Cannot close sell ticket ", OrderTicket(), " error: ", ErrorDescription(GetLastError()));
          }
        }
        if (OrderType() == OP_BUYSTOP)
        {
          if (OrderDelete(OrderTicket(), 4294967295))
          {
            Print("Buy Stop Ticket ", OrderTicket(), " deleted");
            closed_orders_counter = closed_orders_counter + 1;
          }
          else
          {
            Print("Cannot delete buy stop ticket ", OrderTicket(), " error: ", ErrorDescription(GetLastError()));
          }
        }
        if (OrderType() == OP_SELLSTOP)
        {
          if (OrderDelete(OrderTicket(), 4294967295))
          {
            Print("Sell Stop Ticket ", OrderTicket(), " deleted");
            closed_orders_counter = closed_orders_counter + 1;
          }
          else
          {
            Print("Cannot delete sell stop ticket ", OrderTicket(), " error: ", ErrorDescription(GetLastError()));
          }
        }
      }
      order_list_index = order_list_index - 1;
    } while (order_list_index >= 0);
  }
  if (closed_orders_counter <= 0)
    return;
  is_trading_paused = true;
  next_trading_time = iTime(NULL, 1440, 0);
  Print("Closed By ", close_reason);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string SymbProperties()
{
  return "";
}
//+------------------------------------------------------------------+
void AddSymb(int &num, string name, double myp) {}
//+------------------------------------------------------------------+
double GetMyPoint(string symbol = NULL)
{
  return (MarketInfo(symbol == NULL ? Symbol() : symbol, MODE_POINT));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool TradingTime() // fonction simplifiée sans gestion des jours
{
  bool result = false;
  datetime starttime = StrToTime(IntegerToString(Year()) + "." + IntegerToString(Month()) + "." + IntegerToString(Day()) + " " + IntegerToString(TimeStart_Hour) + ":" + IntegerToString(TimeStart_Minute));
  datetime endtime = StrToTime(IntegerToString(Year()) + "." + IntegerToString(Month()) + "." + IntegerToString(Day()) + " " + IntegerToString(TimeEnd_Hour) + ":" + IntegerToString(TimeEnd_Minute));
  if (TimeCurrent() >= starttime && TimeCurrent() <= endtime)
    result = true;
  return (result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int T_Count(int mode, int magic = EMPTY, string symbol = NULL, string comment = "")
{
  int count = 0;
  int itotal = OrdersTotal();
  string str_symbol = Symbol();
  if (symbol != NULL)
    str_symbol = symbol;
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
    {
      if ((OrderSymbol()) == (str_symbol) && (magic == EMPTY || ((OrderMagicNumber() == magic))) && OrderType() == mode)
      {
        if (comment != "")
        {
          if (StringFind(OrderComment(), comment) != -1)
          {
            count++;
          }
        }
        else
        {
          count++;
        }
      }
    }
  }
  return (count);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SummProfit(int Magic, int mode)
{
  int itotal = OrdersTotal();
  double sum_profit = 0.0;
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
    {
      if (OrderSymbol() == Symbol() && (OrderMagicNumber() == Magic) && OrderType() == mode)
      {
        sum_profit += OrderProfit() + OrderCommission() + OrderSwap();
      }
    }
  }
  return (sum_profit);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SummProfitDay(int Magic, int mode)
{
  int itotal = OrdersHistoryTotal();
  double sum_profit = 0.0;
  datetime starttime = StrToTime(IntegerToString(Year()) + "." + IntegerToString(Month()) + "." + IntegerToString(Day()) + " 00:00:00");
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
    {
      if (OrderSymbol() == Symbol() && (OrderMagicNumber() == Magic) && OrderType() == mode)
      {
        if (OrderCloseTime() > starttime)
        {
          sum_profit += OrderProfit() + OrderCommission() + OrderSwap();
        }
      }
    }
  }
  return (sum_profit);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SummProfitYestDay(int Magic, int mode)
{
  int itotal = OrdersHistoryTotal();
  double sum_profit = 0.0;
  datetime starttime = StrToTime(IntegerToString(Year()) + "." + IntegerToString(Month()) + "." + IntegerToString(Day()) + " 00:00:00");
  datetime end_time = starttime;
  starttime -= 86400;
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
    {
      if (OrderSymbol() == Symbol() && (OrderMagicNumber() == Magic) && OrderType() == mode)
      {
        if (OrderCloseTime() > starttime && OrderCloseTime() < end_time)
        {
          sum_profit += OrderProfit() + OrderCommission() + OrderSwap();
        }
      }
    }
  }
  return (sum_profit);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SummProfitMonth(int Magic, int mode)
{
  int itotal = OrdersHistoryTotal();
  double sum_profit = 0.0;
  datetime starttime = StrToTime(IntegerToString(Year()) + "." + IntegerToString(Month()) + ".1 00:00:00");
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
    {
      if (OrderSymbol() == Symbol() && (OrderMagicNumber() == Magic) && OrderType() == mode)
      {
        if (OrderCloseTime() > starttime)
        {
          sum_profit += OrderProfit() + OrderCommission() + OrderSwap();
        }
      }
    }
  }
  return (sum_profit);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double SummProfitYear(int Magic, int mode)
{
  int itotal = OrdersHistoryTotal();
  double sum_profit = 0.0;
  datetime starttime = StrToTime(IntegerToString(Year()) + ".01.1 00:00:00");
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
    {
      if (OrderSymbol() == Symbol() && (OrderMagicNumber() == Magic) && OrderType() == mode)
      {
        if (OrderCloseTime() > starttime)
        {
          sum_profit += OrderProfit() + OrderCommission() + OrderSwap();
        }
      }
    }
  }
  return (sum_profit);
}
//+------------------------------------------------------------------+
double SummProfitWeek(int Magic, int mode)
{
  int itotal = OrdersHistoryTotal();
  double sum_profit = 0.0;
  datetime starttime = StrToTime(IntegerToString(Year()) + "." + IntegerToString(Month()) + "." + IntegerToString(Day()) + " 00:00:00");
  while (TimeDayOfWeek(starttime) != 1)
    starttime -= 86400;
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
    {
      if (OrderSymbol() == Symbol() && (OrderMagicNumber() == Magic) && OrderType() == mode)
      {
        if (OrderCloseTime() > starttime)
        {
          sum_profit += OrderProfit() + OrderCommission() + OrderSwap();
        }
      }
    }
  }
  return (sum_profit);
}
//+------------------------------------------------------------------+
bool FindTrade(int Magic, datetime time_order, int mode)
{
  bool res = false;
  int itotal = OrdersTotal();
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
    {
      if (OrderSymbol() == Symbol() && (OrderMagicNumber() == Magic) && OrderType() == mode)
      {
        if (OrderOpenTime() > time_order)
          return (true);
      }
    }
  }
  itotal = OrdersHistoryTotal();
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
    {
      if (OrderSymbol() == Symbol() && (OrderMagicNumber() == Magic) && OrderType() == mode)
      {
        if (OrderOpenTime() > time_order)
          return (true);
      }
    }
  }
  return (res);
}
//+------------------------------------------------------------------+
void SignalT(char &signal[], int period, int count, int visual_count, int current_int1, double current_double1, string ExpertComment)
{
  ObjectsDeleteAll(0, ExpertComment);
  double ma1, ma2, ma3;
  bool up_trend = true;
  double signal1 = 0.0;
  double signal2 = 0.0;
  double signal3 = 0.0;
  int i;
  double medium_high;
  double medium_low;
  int SignalPeriod = current_int1;
  double step_delta = current_double1;
  double MyPoint = GetMyPoint();
  bool time_filter = false;
  for (i = count - 2; i > 0; i--)
  {
    ma1 = iMA(Symbol(), period, SignalPeriod, 0, MODE_EMA, PRICE_CLOSE, i);
    ma2 = iMA(Symbol(), period, SignalPeriod, 0, MODE_EMA, PRICE_CLOSE, i + 1);
    ma3 = iMA(Symbol(), period, SignalPeriod, 0, MODE_EMA, PRICE_CLOSE, i + 2);
    medium_high = iMA(Symbol(), period, SignalPeriod, 0, MODE_SMA, PRICE_HIGH, i) + step_delta * MyPoint;
    medium_low = iMA(Symbol(), period, SignalPeriod, 0, MODE_SMA, PRICE_LOW, i) - step_delta * MyPoint;
    time_filter = true;
    if (up_trend == true)
    {
      signal2 = signal1;
      signal1 = medium_low;
      if (signal1 < signal2)
        signal1 = signal2;
      if (iHigh(NULL, period, i) < signal1)
      {
        up_trend = false;
        signal[i] = 1;
        signal1 = medium_high;
        if (time_filter)
        {
          if (i < visual_count - 2)
          {
            ChartTrendLine(ExpertComment + "_buy" + TimeToString(iTime(NULL, period, i)), iTime(NULL, period, i + 1), signal2, iTime(NULL, period, i), signal2, 1, clrDodgerBlue);
          }
        }
        else
        {
          if (i < visual_count - 2)
          {
            ChartTrendLine(ExpertComment + "_buy" + TimeToString(iTime(NULL, period, i)), iTime(NULL, period, i + 1), signal2, iTime(NULL, period, i), signal2, 1, Gray1);
          }
        }
      }
      else
      {
        if (time_filter)
        {
          if (i < visual_count - 2)
          {
            ChartTrendLine(ExpertComment + "_buy" + TimeToString(iTime(NULL, period, i)), iTime(NULL, period, i + 1), signal2, iTime(NULL, period, i), signal1, 1, clrDodgerBlue);
          }
        }
        else
        {
          if (i < visual_count - 2)
          {
            ChartTrendLine(ExpertComment + "_buy" + TimeToString(iTime(NULL, period, i)), iTime(NULL, period, i + 1), signal2, iTime(NULL, period, i), signal1, 1, Gray1);
          }
        }
      }
    }
    else
    {
      signal2 = signal1;
      signal1 = medium_high;
      if (signal1 > signal2)
        signal1 = signal2;
      if (iLow(NULL, period, i) > signal1)
      {
        up_trend = true;
        signal[i] = -1;
        signal1 = medium_low;
        if (time_filter)
        {
          if (i < visual_count - 2)
            ChartTrendLine(ExpertComment + "_buy" + TimeToString(iTime(NULL, period, i)), iTime(NULL, period, i + 1), signal2, iTime(NULL, period, i), signal2, 1, clrRed);
        }
        else
        {
          if (i < visual_count - 2)
            ChartTrendLine(ExpertComment + "_buy" + TimeToString(iTime(NULL, period, i)), iTime(NULL, period, i + 1), signal2, iTime(NULL, period, i), signal2, 1, Gray1);
        }
      }
      else
      {
        if (time_filter)
        {
          if (i < visual_count - 2)
            ChartTrendLine(ExpertComment + "_buy" + TimeToString(iTime(NULL, period, i)), iTime(NULL, period, i + 1), signal2, iTime(NULL, period, i), signal1, 1, clrRed);
        }
        else
        {
          if (i < visual_count - 2)
            ChartTrendLine(ExpertComment + "_buy" + TimeToString(iTime(NULL, period, i)), iTime(NULL, period, i + 1), signal2, iTime(NULL, period, i), signal1, 1, Gray1);
        }
      }
    }
  }
}

//+------------------------------------------------------------------+
void ChartTrendLine(string object_name, datetime time1, double price1, datetime time2, double price2, int width, color Color, ENUM_LINE_STYLE style = STYLE_DOT)
{
  if (ObjectFind(object_name) == -1)
  {
    ObjectCreate(object_name, OBJ_TREND, 0, time1, price1, time2, price2);
  }
  ObjectSet(object_name, OBJPROP_TIME1, time1);
  ObjectSet(object_name, OBJPROP_TIME2, time2);
  ObjectSet(object_name, OBJPROP_PRICE1, price1);
  ObjectSet(object_name, OBJPROP_PRICE2, price2);
  ObjectSet(object_name, OBJPROP_WIDTH, width);
  ObjectSet(object_name, OBJPROP_STYLE, style);
  ObjectSet(object_name, OBJPROP_COLOR, Color);
  ObjectSet(object_name, OBJPROP_RAY, false);
  ObjectSet(object_name, OBJPROP_BACK, true);
}
//+------------------------------------------------------------------+
double SummLot(int Magic, int mode)
{
  int itotal = OrdersTotal();
  double sum_lot = 0.0;
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
    {
      if (OrderSymbol() == Symbol() && (OrderMagicNumber() == Magic) && OrderType() == mode)
      {
        sum_lot += OrderLots();
      }
    }
  }
  return (sum_lot);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool T_Buy(double lot, double sl_pips, double tp_pips, int magic, string symbol = NULL, string comment = NULL, int Slipping = 5, int RequoteAttempts = 3, color Color = clrBlue)
{
  bool result = false;
  string str_symbol = Symbol();
  if (symbol != NULL)
    str_symbol = symbol;
  int my_digits = int(MarketInfo(str_symbol, MODE_DIGITS));
  double dLot = CheckLot(str_symbol, OP_BUY, MarketInfo(str_symbol, MODE_ASK), lot);
  if (AccountFreeMarginCheck(str_symbol, OP_BUY, dLot) <= 0)
  {
    Alert("We have no money for buy " + str_symbol + " " + DoubleToString(dLot, 2) + " lots!");
    return (result);
  }
  for (int i = 0; i < RequoteAttempts; i++)
  {
    if (!IsTesting())
    {
      while (!IsTradeAllowed())
        Sleep(5000);
      RefreshRates();
    }
    double dPrice = NormalizeDouble(MarketInfo(str_symbol, MODE_ASK), my_digits);
    int res = OrderSend(str_symbol, OP_BUY, dLot, dPrice, Slipping, 0.0, 0.0, comment, magic, 0, Color);
    if (res > 0)
    {
      if (OrderSelect(res, SELECT_BY_TICKET, MODE_TRADES))
      {
        result = true;
        if (!IsOptimization())
          Print(str_symbol + " opened Order Buy № " + IntegerToString(res) + " by price " + DoubleToString(OrderOpenPrice(), my_digits));
        double dSL = 0.0;
        double dTP = 0.0;
        double my_point = GetMyPoint(str_symbol);
        double my_bid = MarketInfo(str_symbol, MODE_BID);
        double my_stoplevel = ((MarketInfo(str_symbol, MODE_STOPLEVEL) + MarketInfo(str_symbol, MODE_FREEZELEVEL) + 1.0) * MarketInfo(str_symbol, MODE_POINT)) / my_point;
        if (sl_pips > 0.0)
        {
          dSL = NormalizeDouble(OrderOpenPrice() - sl_pips * my_point, my_digits);
          if (dSL > NormalizeDouble(my_bid - my_stoplevel * my_point, my_digits))
            dSL = NormalizeDouble(my_bid - my_stoplevel * my_point, my_digits);
          if (OrderModify(res, OrderOpenPrice(), dSL, 0, 0, Color))
          {
            if (!IsOptimization())
              Print(str_symbol + " Order Buy № " + IntegerToString(res) + " successfully set SL=" + DoubleToString(dSL, my_digits));
          }
          else
          {
            if (!IsOptimization())
            {
              int last_error = GetLastError();
              Print(str_symbol + " Order Buy № " + IntegerToString(res) + " set SL=" + DoubleToString(dSL, my_digits) + " error=" + IntegerToString(last_error));
              CheckError(last_error);
            }
          }
        }
        if (tp_pips > 0.0)
        {
          dTP = NormalizeDouble(OrderOpenPrice() + tp_pips * my_point, my_digits);
          if (dTP < NormalizeDouble(my_bid + my_stoplevel * my_point, my_digits))
            dTP = NormalizeDouble(my_bid + my_stoplevel * my_point, my_digits);
          if (OrderModify(res, OrderOpenPrice(), dSL, dTP, 0, Color))
          {
            if (!IsOptimization())
              Print(str_symbol + " Order Buy № " + IntegerToString(res) + " successfully set TP=" + DoubleToString(dTP, my_digits));
          }
          else
          {
            if (!IsOptimization())
            {
              int last_error_2 = GetLastError();
              Print(str_symbol + " Order Buy № " + IntegerToString(res) + " set TP=" + DoubleToString(dTP, my_digits) + " error=" + IntegerToString(last_error_2));
              CheckError(last_error_2);
            }
          }
        }
      }
      break;
    }
    else
    {
      CheckError(GetLastError());
      Sleep(100);
    }
  }
  return (result);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool T_Sell(double lot, double sl_pips, double tp_pips, int magic, string symbol = NULL, string comment = NULL, int Slipping = 5, int RequoteAttempts = 3, color Color = clrRed)
{
  bool result = false;
  string str_symbol = Symbol();
  if (symbol != NULL)
    str_symbol = symbol;
  int my_digits = int(MarketInfo(str_symbol, MODE_DIGITS));
  double dLot = CheckLot(str_symbol, OP_SELL, MarketInfo(str_symbol, MODE_BID), lot);
  if (AccountFreeMarginCheck(str_symbol, OP_SELL, dLot) <= 0)
  {
    Alert("We have no money for sell " + str_symbol + " " + DoubleToString(dLot, 2) + " lots!");
    return (result);
  }
  for (int i = 0; i < RequoteAttempts; i++)
  {
    if (!IsTesting())
    {
      while (!IsTradeAllowed())
        Sleep(5000);
      RefreshRates();
    }
    double dPrice = NormalizeDouble(MarketInfo(str_symbol, MODE_BID), my_digits);
    int res = OrderSend(str_symbol, OP_SELL, dLot, dPrice, Slipping, 0, 0, comment, magic, 0, Color);
    if (res > 0)
    {
      if (OrderSelect(res, SELECT_BY_TICKET, MODE_TRADES))
      {
        result = true;
        if (!IsOptimization())
          Print(str_symbol + " opened Order Sell № " + IntegerToString(res) + " by price " + DoubleToString(OrderOpenPrice(), my_digits));
        double dSL = 0.0;
        double dTP = 0.0;
        double my_point = GetMyPoint(str_symbol);
        double my_ask = MarketInfo(str_symbol, MODE_ASK);
        double my_stoplevel = ((MarketInfo(str_symbol, MODE_STOPLEVEL) + MarketInfo(str_symbol, MODE_FREEZELEVEL) + 1.0) * MarketInfo(str_symbol, MODE_POINT)) / my_point;
        if (sl_pips > 0.0)
        {
          dSL = NormalizeDouble(OrderOpenPrice() + sl_pips * my_point, my_digits);
          if (dSL < NormalizeDouble(my_ask + my_stoplevel * my_point, my_digits))
            dSL = NormalizeDouble(my_ask + my_stoplevel * my_point, my_digits);
          if (OrderModify(res, OrderOpenPrice(), dSL, 0, 0, Color))
          {
            if (!IsOptimization())
              Print(str_symbol + " Order Sell № " + IntegerToString(res) + " successfully set SL=" + DoubleToString(dSL, my_digits));
          }
          else
          {
            if (!IsOptimization())
            {
              int last_error = GetLastError();
              Print(str_symbol + " Order Sell № " + IntegerToString(res) + " set SL=" + DoubleToString(dSL, my_digits) + " error=" + IntegerToString(last_error));
              CheckError(last_error);
            }
          }
        }
        if (tp_pips > 0.0)
        {
          dTP = NormalizeDouble(OrderOpenPrice() - tp_pips * my_point, my_digits);
          if (dTP > NormalizeDouble(my_ask - my_stoplevel * my_point, my_digits))
            dTP = NormalizeDouble(my_ask - my_stoplevel * my_point, my_digits);
          if (OrderModify(res, OrderOpenPrice(), dSL, dTP, 0, Color))
          {
            if (!IsOptimization())
              Print(str_symbol + " Order Sell № " + IntegerToString(res) + " successfully set TP=" + DoubleToString(dTP, my_digits));
          }
          else
          {
            if (!IsOptimization())
            {
              int last_error_2 = GetLastError();
              Print(str_symbol + " Order Sell № " + IntegerToString(res) + " set TP=" + DoubleToString(dTP, my_digits) + " error=" + IntegerToString(last_error_2));
              CheckError(last_error_2);
            }
          }
        }
      }
      break;
    }
    else
    {
      CheckError(GetLastError());
      Sleep(100);
    }
  }
  return (result);
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CheckLot(string symbol, ENUM_ORDER_TYPE ord_type, double price_open, double lot)
{
  if (lot < SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN))
    lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
  if (lot > SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX))
    lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
  double volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
  int ratio = 1;
  if (volume_step > 0.0)
    ratio = (int)MathRound(lot / volume_step);
  lot = ratio * volume_step;
  return (lot);
}
//+------------------------------------------------------------------+
void CheckError(int Error, bool Alert_show = false)
{
  string err_text = Symbol() + " " + TF_str(Period()) + " Error " + IntegerToString(Error) + ". ";
  if (Error == ERR_NO_ERROR)
  {
    err_text += "No error returned.";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_RESULT)
  {
    err_text += "No error returned, but the result is unknown";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_COMMON_ERROR)
  {
    err_text += "Common error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INVALID_TRADE_PARAMETERS)
  {
    err_text += "Invalid trade parameters";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_SERVER_BUSY)
  {
    err_text += "Trade server is busy";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_OLD_VERSION)
  {
    err_text += "Old version of the client terminal";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_CONNECTION)
  {
    err_text += "No connection with trade server";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NOT_ENOUGH_RIGHTS)
  {
    err_text += "Not enough rights";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TOO_FREQUENT_REQUESTS)
  {
    err_text += "Too frequent requests";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_MALFUNCTIONAL_TRADE)
  {
    err_text += "Malfunctional trade operation";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_ACCOUNT_DISABLED)
  {
    err_text += "Account disabled";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INVALID_ACCOUNT)
  {
    err_text += "Invalid account";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TRADE_TIMEOUT)
  {
    err_text += "Trade timeout";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INVALID_PRICE)
  {
    err_text += "Invalid price";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INVALID_STOPS)
  {
    err_text += "Invalid stops";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INVALID_TRADE_VOLUME)
  {
    err_text += "Invalid trade volume";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_MARKET_CLOSED)
  {
    err_text += "Market is closed";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TRADE_DISABLED)
  {
    err_text += "Trade is disabled";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NOT_ENOUGH_MONEY)
  {
    err_text += "Not enough money";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_PRICE_CHANGED)
  {
    err_text += "Price changed";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_OFF_QUOTES)
  {
    err_text += "Off quotes";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_BROKER_BUSY)
  {
    err_text += "Broker is busy";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_REQUOTE)
  {
    err_text += "Requote";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_ORDER_LOCKED)
  {
    err_text += "Order is locked";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_LONG_POSITIONS_ONLY_ALLOWED)
  {
    err_text += "Buy orders only allowed";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TOO_MANY_REQUESTS)
  {
    err_text += "Too many requests";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TRADE_MODIFY_DENIED)
  {
    err_text += "Modification denied because order is too close to market";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TRADE_CONTEXT_BUSY)
  {
    err_text += "Trade context is busy";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TRADE_EXPIRATION_DENIED)
  {
    err_text += "Expirations are denied by broker";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TRADE_TOO_MANY_ORDERS)
  {
    err_text += "The amount of open and pending orders has reached the limit set by the broker";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TRADE_HEDGE_PROHIBITED)
  {
    err_text += "An attempt to open an order opposite to the existing one when hedging is disabled";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TRADE_PROHIBITED_BY_FIFO)
  {
    err_text += "An attempt to close an order contravening the FIFO rule";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_MQLERROR)
  {
    err_text += "No error returned";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_WRONG_FUNCTION_POINTER)
  {
    err_text += "Wrong function pointer";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_ARRAY_INDEX_OUT_OF_RANGE)
  {
    err_text += "Array index is out of range";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_MEMORY_FOR_CALL_STACK)
  {
    err_text += "No memory for function call stack";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_RECURSIVE_STACK_OVERFLOW)
  {
    err_text += "Recursive stack overflow";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NOT_ENOUGH_STACK_FOR_PARAM)
  {
    err_text += "Not enough stack for parameter";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_MEMORY_FOR_PARAM_STRING)
  {
    err_text += "No memory for parameter string";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_MEMORY_FOR_TEMP_STRING)
  {
    err_text += "No memory for temp string";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NOT_INITIALIZED_STRING)
  {
    err_text += "Not initialized string";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NOT_INITIALIZED_ARRAYSTRING)
  {
    err_text += "Not initialized string in array";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_MEMORY_FOR_ARRAYSTRING)
  {
    err_text += "No memory for array string";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TOO_LONG_STRING)
  {
    err_text += "Too long string";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_REMAINDER_FROM_ZERO_DIVIDE)
  {
    err_text += "Remainder from zero divide";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_ZERO_DIVIDE)
  {
    err_text += "Zero divide";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_UNKNOWN_COMMAND)
  {
    err_text += "Unknown command";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_WRONG_JUMP)
  {
    err_text += "Wrong jump (never generated error)";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NOT_INITIALIZED_ARRAY)
  {
    err_text += "Not initialized array";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_DLL_CALLS_NOT_ALLOWED)
  {
    err_text += "DLL calls are not allowed";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_CANNOT_LOAD_LIBRARY)
  {
    err_text += "Cannot load library";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_CANNOT_CALL_FUNCTION)
  {
    err_text += "Cannot call function";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_EXTERNAL_CALLS_NOT_ALLOWED)
  {
    err_text += "Expert function calls are not allowed";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_MEMORY_FOR_RETURNED_STR)
  {
    err_text += "Not enough memory for temp string returned from function";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_SYSTEM_BUSY)
  {
    err_text += "System is busy (never generated error)";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_DLLFUNC_CRITICALERROR)
  {
    err_text += "DLL-function call critical error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INTERNAL_ERROR)
  {
    err_text += "Internal error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_OUT_OF_MEMORY)
  {
    err_text += "Out of memory";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INVALID_POINTER)
  {
    err_text += "Invalid pointer";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FORMAT_TOO_MANY_FORMATTERS)
  {
    err_text += "Too many formatters in the format function";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FORMAT_TOO_MANY_PARAMETERS)
  {
    err_text += "Parameters count exceeds formatters count";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_ARRAY_INVALID)
  {
    err_text += "Invalid array";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_CHART_NOREPLY)
  {
    err_text += "No reply from chart";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INVALID_FUNCTION_PARAMSCNT)
  {
    err_text += "Invalid function parameters count";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INVALID_FUNCTION_PARAMVALUE)
  {
    err_text += "Invalid function parameter value";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_STRING_FUNCTION_INTERNAL)
  {
    err_text += "String function internal error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_SOME_ARRAY_ERROR)
  {
    err_text += "Some array error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INCORRECT_SERIESARRAY_USING)
  {
    err_text += "Incorrect series array using";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_CUSTOM_INDICATOR_ERROR)
  {
    err_text += "Custom indicator error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INCOMPATIBLE_ARRAYS)
  {
    err_text += "Arrays are incompatible";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_GLOBAL_VARIABLES_PROCESSING)
  {
    err_text += "Global variables processing error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_GLOBAL_VARIABLE_NOT_FOUND)
  {
    err_text += "Global variable not found";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FUNC_NOT_ALLOWED_IN_TESTING)
  {
    err_text += "Function is not allowed in testing mode";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FUNCTION_NOT_CONFIRMED)
  {
    err_text += "Function is not allowed for call";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_SEND_MAIL_ERROR)
  {
    err_text += "Send mail error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_STRING_PARAMETER_EXPECTED)
  {
    err_text += "String parameter expected";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INTEGER_PARAMETER_EXPECTED)
  {
    err_text += "Integer parameter expected";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_DOUBLE_PARAMETER_EXPECTED)
  {
    err_text += "Double parameter expected";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_ARRAY_AS_PARAMETER_EXPECTED)
  {
    err_text += "Array as parameter expected";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_HISTORY_WILL_UPDATED)
  {
    err_text += "Requested history data is in updating state";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TRADE_ERROR)
  {
    err_text += "Internal trade error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_RESOURCE_NOT_FOUND)
  {
    err_text += "Resource not found";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_RESOURCE_NOT_SUPPORTED)
  {
    err_text += "Resource not supported";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_RESOURCE_DUPLICATED)
  {
    err_text += "Duplicate resource";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INDICATOR_CANNOT_INIT)
  {
    err_text += "Custom indicator cannot initialize";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INDICATOR_CANNOT_LOAD)
  {
    err_text += "Cannot load custom indicator";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_HISTORY_DATA)
  {
    err_text += "No history data";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_MEMORY_FOR_HISTORY)
  {
    err_text += "No memory for history data";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_MEMORY_FOR_INDICATOR)
  {
    err_text += "Not enough memory for indicator calculation";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_END_OF_FILE)
  {
    err_text += "End of file";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_SOME_FILE_ERROR)
  {
    err_text += "Some file error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_WRONG_FILE_NAME)
  {
    err_text += "Wrong file name";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TOO_MANY_OPENED_FILES)
  {
    err_text += "Too many opened files";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_CANNOT_OPEN_FILE)
  {
    err_text += "Cannot open file";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INCOMPATIBLE_FILEACCESS)
  {
    err_text += "Incompatible access to a file";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_ORDER_SELECTED)
  {
    err_text += "No order selected";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_UNKNOWN_SYMBOL)
  {
    err_text += "Unknown symbol";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INVALID_PRICE_PARAM)
  {
    err_text += "Invalid price";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_INVALID_TICKET)
  {
    err_text += "Invalid ticket";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TRADE_NOT_ALLOWED)
  {
    err_text += "Trade is not allowed. Enable checkbox \"Allow live trading\" in the Expert Advisor properties";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_LONGS_NOT_ALLOWED)
  {
    err_text += "Longs are not allowed. Check the Expert Advisor properties";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_SHORTS_NOT_ALLOWED)
  {
    err_text += "Shorts are not allowed. Check the Expert Advisor properties";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_TRADE_EXPERT_DISABLED_BY_SERVER)
  {
    err_text += "Automated trading by Expert Advisors/Scripts disabled by trade server";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_OBJECT_ALREADY_EXISTS)
  {
    err_text += "Object already exists";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_UNKNOWN_OBJECT_PROPERTY)
  {
    err_text += "Unknown object property";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_OBJECT_DOES_NOT_EXIST)
  {
    err_text += "Object does not exist";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_UNKNOWN_OBJECT_TYPE)
  {
    err_text += "Unknown object type";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_OBJECT_NAME)
  {
    err_text += "No object name";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_OBJECT_COORDINATES_ERROR)
  {
    err_text += "Object coordinates error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NO_SPECIFIED_SUBWINDOW)
  {
    err_text += "No specified subwindow";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_SOME_OBJECT_ERROR)
  {
    err_text += "Graphical object error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_CHART_PROP_INVALID)
  {
    err_text += "Unknown chart property";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_CHART_NOT_FOUND)
  {
    err_text += "Chart not found";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_CHARTWINDOW_NOT_FOUND)
  {
    err_text += "Chart subwindow not found";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_CHARTINDICATOR_NOT_FOUND)
  {
    err_text += "Chart indicator not found";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_SYMBOL_SELECT)
  {
    err_text += "Symbol select error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NOTIFICATION_ERROR)
  {
    err_text += "Notification error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NOTIFICATION_PARAMETER)
  {
    err_text += "Notification parameter error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NOTIFICATION_SETTINGS)
  {
    err_text += "Notifications disabled";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_NOTIFICATION_TOO_FREQUENT)
  {
    err_text += "Notification send too frequent";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FTP_NOSERVER)
  {
    err_text += "FTP server is not specified";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FTP_NOLOGIN)
  {
    err_text += "FTP login is not specified";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FTP_CONNECT_FAILED)
  {
    err_text += "FTP connection failed";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FTP_CLOSED)
  {
    err_text += "FTP connection closed";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FTP_CHANGEDIR)
  {
    err_text += "FTP path not found on server";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FTP_FILE_ERROR)
  {
    err_text += "File not found in the MQL4\\Files directory to send on FTP server";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FTP_ERROR)
  {
    err_text += "Common error during FTP data transmission";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_TOO_MANY_OPENED)
  {
    err_text += "Too many opened files";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_WRONG_FILENAME)
  {
    err_text += "Wrong file name";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_TOO_LONG_FILENAME)
  {
    err_text += "Too long file name";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_CANNOT_OPEN)
  {
    err_text += "Cannot open file";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_BUFFER_ALLOCATION_ERROR)
  {
    err_text += "Text file buffer allocation error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_CANNOT_DELETE)
  {
    err_text += "Cannot delete file";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_INVALID_HANDLE)
  {
    err_text += "Invalid file handle (file closed or was not opened)";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_WRONG_HANDLE)
  {
    err_text += "Wrong file handle (handle index is out of handle table)";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_NOT_TOWRITE)
  {
    err_text += "File must be opened with FILE_WRITE flag";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_NOT_TOREAD)
  {
    err_text += "File must be opened with FILE_READ flag";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_NOT_BIN)
  {
    err_text += "File must be opened with FILE_BIN flag";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_NOT_TXT)
  {
    err_text += "File must be opened with FILE_TXT flag";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_NOT_TXTORCSV)
  {
    err_text += "File must be opened with FILE_TXT or FILE_CSV flag";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_READ_ERROR)
  {
    err_text += "File read error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_WRITE_ERROR)
  {
    err_text += "File write error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_BIN_STRINGSIZE)
  {
    err_text += "String size must be specified for binary file";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_INCOMPATIBLE)
  {
    err_text += "Incompatible file (for string arrays-TXT, for others-BIN)";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_IS_DIRECTORY)
  {
    err_text += "File is directory not file";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_NOT_EXIST)
  {
    err_text += "File does not exist";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_CANNOT_REWRITE)
  {
    err_text += "File cannot be rewritten";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_WRONG_DIRECTORYNAME)
  {
    err_text += "Wrong directory name";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_DIRECTORY_NOT_EXIST)
  {
    err_text += "Directory does not exist";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_NOT_DIRECTORY)
  {
    err_text += "Specified file is not directory";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_CANNOT_DELETE_DIRECTORY)
  {
    err_text += "Cannot delete directory";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_CANNOT_CLEAN_DIRECTORY)
  {
    err_text += "Cannot clean directory";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_ARRAYRESIZE_ERROR)
  {
    err_text += "Array resize error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_STRINGRESIZE_ERROR)
  {
    err_text += "String resize error";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_FILE_STRUCT_WITH_OBJECTS)
  {
    err_text += "Structure contains strings or dynamic arrays";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_WEBREQUEST_INVALID_ADDRESS)
  {
    err_text += "Invalid URL";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_WEBREQUEST_CONNECT_FAILED)
  {
    err_text += "Failed to connect to specified URL";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_WEBREQUEST_TIMEOUT)
  {
    err_text += "Timeout exceeded";
    EPrint(err_text, Alert_show);
  }
  if (Error == ERR_WEBREQUEST_REQUEST_FAILED)
  {
    err_text += "HTTP request failed";
    EPrint(err_text, Alert_show);
  }
}
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void EPrint(string err_text, bool Alert_show)
{
  Print(err_text);
  if (Alert_show)
    Alert(err_text);
}
//+------------------------------------------------------------------+
string TF_str(int period)
{
  string TF = "";
  if (period == PERIOD_M1)
    TF = "M1";
  if (period == PERIOD_M5)
    TF = "M5";
  if (period == PERIOD_M15)
    TF = "M15";
  if (period == PERIOD_M30)
    TF = "M30";
  if (period == PERIOD_H1)
    TF = "H1";
  if (period == PERIOD_H4)
    TF = "H4";
  if (period == PERIOD_D1)
    TF = "D1";
  if (period == PERIOD_W1)
    TF = "W1";
  if (period == PERIOD_MN1)
    TF = "MN1";
  return (TF);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
double AveragePrice(int Magic, int order_type)
{
  int itotal = OrdersTotal();
  double temp_average = 0.0;
  double sum_lots = 0.0;
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
    {
      if (OrderSymbol() == Symbol() && (OrderMagicNumber() == Magic) && OrderType() == order_type)
      {
        temp_average += OrderOpenPrice() * OrderLots();
        sum_lots += OrderLots();
      }
    }
  }
  if (sum_lots > 0.0)
    temp_average /= sum_lots;
  return (temp_average);
}
//+------------------------------------------------------------------+
// Функция устанавливает ТП для бай ордеров
void TPBuy(int Magic, double take)
{
  int itotal = OrdersTotal();
  bool result = false;
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
    {
      if (OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() == OP_BUY)
      {
        if (DoubleToString(OrderTakeProfit(), _Digits) != DoubleToString(NormalizeDouble(take, _Digits), _Digits))
        {
          ResetLastError();
          if (MathAbs(Bid - take) > (MarketInfo(Symbol(), MODE_FREEZELEVEL) + MarketInfo(Symbol(), MODE_STOPLEVEL)) * Point() + Point())
            if (!OrderModify(OrderTicket(), OrderOpenPrice(), OrderStopLoss(), take, NULL, clrNONE))
              Print("TPBuy Order modify error " + IntegerToString(GetLastError()));
        }
      }
    }
  }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// Функция устанавливает СЛ для бай ордеров
void SLBuy(int Magic, double sl)
{
  int itotal = OrdersTotal();
  bool result = false;
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
    {
      if (OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() == OP_BUY)
      {
        if (DoubleToString(OrderStopLoss(), Digits) != DoubleToString(NormalizeDouble(sl, _Digits), Digits))
        {
          ResetLastError();
          if (MathAbs(Bid - sl) > (MarketInfo(Symbol(), MODE_FREEZELEVEL) + MarketInfo(Symbol(), MODE_STOPLEVEL)) * Point() + Point())
            if (!OrderModify(OrderTicket(), OrderOpenPrice(), sl, OrderTakeProfit(), NULL, clrNONE))
              Print("SLBuy Order modify error " + IntegerToString(GetLastError()));
        }
      }
    }
  }
}
////Функция устанавливает ТП для селл ордеров
void TPSell(int Magic, double take)
{
  int itotal = OrdersTotal();
  bool result = false;
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
    {
      if (OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() == OP_SELL)
      {
        if (DoubleToString(OrderTakeProfit(), Digits) != DoubleToString(NormalizeDouble(take, _Digits), Digits))
        {
          ResetLastError();
          if (MathAbs(Ask - take) > (MarketInfo(Symbol(), MODE_FREEZELEVEL) + MarketInfo(Symbol(), MODE_STOPLEVEL)) * Point() + Point())
            if (!OrderModify(OrderTicket(), OrderOpenPrice(), OrderStopLoss(), take, NULL, clrNONE))
              Print("TPSell Order modify error " + IntegerToString(GetLastError()));
        }
      }
    }
  }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
// Функция устанавливает СЛ для селл ордеров
void SLSell(int Magic, double sl)
{
  int itotal = OrdersTotal();
  bool result = false;
  for (int i = 0; i < itotal; i++)
  {
    if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
    {
      if (OrderSymbol() == Symbol() && OrderMagicNumber() == Magic && OrderType() == OP_SELL)
      {
        if (DoubleToString(OrderStopLoss(), Digits) != DoubleToString(NormalizeDouble(sl, _Digits), Digits))
        {
          ResetLastError();
          if (MathAbs(Ask - sl) > (MarketInfo(Symbol(), MODE_FREEZELEVEL) + MarketInfo(Symbol(), MODE_STOPLEVEL)) * Point() + Point())
            if (!OrderModify(OrderTicket(), OrderOpenPrice(), sl, OrderTakeProfit(), NULL, clrNONE))
              Print("SLSell Order modify error " + IntegerToString(GetLastError()));
        }
      }
    }
  }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ChartLabel(string object_name, int sub_win, string text, datetime time1, double price, color Color, ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER, int f_size = 12, string font_name = "Arial", int Angle = 0, bool back = true, bool selectable = true)
{
  if (ObjectFind(object_name) == -1)
  {
    ObjectCreate(object_name, OBJ_TEXT, sub_win, time1, price);
  }
  ObjectSet(object_name, OBJPROP_TIME1, time1);
  ObjectSet(object_name, OBJPROP_PRICE1, price);
  ObjectSetText(object_name, text, f_size, font_name, Color);
  ObjectSet(object_name, OBJPROP_ANCHOR, anchor);
  ObjectSet(object_name, OBJPROP_ANGLE, Angle);
  ObjectSet(object_name, OBJPROP_BACK, back);
  ObjectSet(object_name, OBJPROP_SELECTABLE, selectable);
}
//+------------------------------------------------------------------+

// --- Fix: Add stubs for missing functions ---
void CloseAllBuy(int magic)
{
  // TODO: Implement logic to close all buy orders with the given magic number
}

void CloseAllSell(int magic)
{
  // TODO: Implement logic to close all sell orders with the given magic number
}
//+------------------------------------------------------------------+

// Function to adapt TP/Tral/TralStart automatically by symbol if enabled
void SetTP_SL_BySymbol()
{
   if(!AutoTPTralBySymbol) return; // If option is off, do not change values

   string sym = Symbol();
   if(StringFind(sym, "XAU") == 0 || StringFind(sym, "XAG") == 0)
   {
      TakeProfit = 500;
      Tral = 300;
      TralStart = 200;
   }
   else if(StringFind(sym, "JPY") > 0)
   {
      if(StringFind(sym, "GBP") == 0) // GBPJPY
      {
         TakeProfit = 60;
         Tral = 40;
         TralStart = 20;
      }
      else if(StringFind(sym, "EUR") == 0) // EURJPY
      {
         TakeProfit = 40;
         Tral = 25;
         TralStart = 15;
      }
      else
      {
         TakeProfit = 35;
         Tral = 22;
         TralStart = 12;
      }
   }
   else if(StringFind(sym, "EURGBP") == 0 || StringFind(sym, "EURCHF") == 0)
   {
      TakeProfit = 25;
      Tral = 15;
      TralStart = 8;
   }
   else if(StringFind(sym, "GBP") == 0)
   {
      TakeProfit = 40;
      Tral = 25;
      TralStart = 15;
   }
   else
   {
      TakeProfit = 30;
      Tral = 20;
      TralStart = 10;
   }
}