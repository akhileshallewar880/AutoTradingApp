import uuid
from app.core.logging import logger
from app.services.data_service import data_service
from app.services.order_service import order_service
from app.services.zerodha_service import zerodha_service
from app.engines.strategy_engine import strategy_engine
from app.engines.risk_engine import risk_engine
from app.agents.llm_agent import llm_agent
from app.models.request_models import AgentRunRequest
from app.models.response_models import AgentRunResponse, TradeSignal, TradeRecommendationResponse
from app.models.trade_models import Trade
from app.storage.database import db # Will implement next
from typing import List

class TradingAgent:
    def __init__(self):
        pass

    async def run(self, request: AgentRunRequest) -> AgentRunResponse:
        execution_id = str(uuid.uuid4())
        logger.info(f"Starting Trading Agent Run: {execution_id}")

        # 1. Fetch Candidates (High Volume Stocks)
        # In a real app, this finds potential stocks from the Nifty500 list
        candidates = await data_service.get_top_volume_stocks(limit=request.number_of_stocks)
        logger.info(f"Fetched {len(candidates)} candidates.")

        market_data_batch = []
        
        # 2. Fetch Data & Apply Deterministic Strategy
        for instrument in candidates:
            # Simplification: using instrument_token if available or just mocking based on simple list
            token = instrument.get('instrument_token')
            symbol = instrument.get('tradingsymbol')
            
            if not token: 
                continue

            df = await data_service.get_candle_data(token, request.timeframe)
            if df.empty:
                continue

            analysis = strategy_engine.apply_technical_analysis(df)
            if analysis:
                analysis['symbol'] = symbol
                analysis['instrument_token'] = token
                market_data_batch.append(analysis)

        # 3. LLM Reasoning
        if not market_data_batch:
            logger.warning("No market data passed strategy filters.")
            return AgentRunResponse(execution_id=execution_id, status="COMPLETED_NO_TRADES", generated_trades=[])

        llm_response: TradeRecommendationResponse = await llm_agent.analyze_opportunities(market_data_batch)
        
        executed_trades = []

        # 4. Risk & Execution
        margins = await zerodha_service.get_margins()
        # available_cash = margins.get('equity', {}).get('net', 0)
        available_cash = 100000 # MOCKING CAPITAL for safety/demo

        for signal in llm_response.trades:
            if signal.action == "BUY": # Supporting Long only for now
                quantity = risk_engine.calculate_quantity(
                    entry_price=signal.entry_price,
                    stop_loss=signal.stop_loss,
                    risk_per_trade=request.risk_percent,
                    capital=available_cash
                )

                if quantity > 0:
                    order_id = await order_service.execute_trade(
                        symbol=signal.stock_symbol,
                        quantity=quantity,
                        price=signal.entry_price,
                        stop_loss=signal.stop_loss,
                        target=signal.target_price
                    )
                    
                    if order_id:
                        # Log Trade
                        trade = Trade(
                            id=str(order_id),
                            symbol=signal.stock_symbol,
                            entry_price=signal.entry_price,
                            stop_loss=signal.stop_loss,
                            target_price=signal.target_price,
                            quantity=quantity,
                            risk_amount=(signal.entry_price - signal.stop_loss) * quantity,
                            status="OPEN"
                        )
                        await db.save_trade(trade)
                        executed_trades.append(signal)

        return AgentRunResponse(
            execution_id=execution_id,
            status="COMPLETED",
            generated_trades=executed_trades
        )

trading_agent = TradingAgent()
