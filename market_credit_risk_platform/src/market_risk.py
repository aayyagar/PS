"""Market risk metrics for portfolio analytics."""

from __future__ import annotations

import numpy as np
import pandas as pd


def calculate_returns(prices: pd.DataFrame) -> pd.DataFrame:
    """Convert asset prices into daily percentage returns."""
    return prices.pct_change().dropna()


def portfolio_returns(returns: pd.DataFrame, weights: np.ndarray) -> pd.Series:
    """Calculate weighted portfolio daily returns."""
    weights = np.asarray(weights, dtype=float)
    weights = weights / weights.sum()
    return returns.dot(weights)


def value_at_risk(returns: pd.Series, confidence: float = 0.95) -> float:
    """Historical VaR as a positive loss number."""
    return float(-np.percentile(returns, (1 - confidence) * 100))


def expected_shortfall(returns: pd.Series, confidence: float = 0.95) -> float:
    """Average loss beyond VaR as a positive loss number."""
    threshold = np.percentile(returns, (1 - confidence) * 100)
    tail_losses = returns[returns <= threshold]
    return float(-tail_losses.mean())


def max_drawdown(returns: pd.Series) -> float:
    """Maximum peak-to-trough portfolio loss."""
    cumulative = (1 + returns).cumprod()
    running_max = cumulative.cummax()
    drawdown = cumulative / running_max - 1
    return float(drawdown.min())


def sharpe_ratio(returns: pd.Series, risk_free_rate: float = 0.02) -> float:
    """Annualized Sharpe ratio using daily returns."""
    daily_rf = risk_free_rate / 252
    excess = returns - daily_rf
    if returns.std() == 0:
        return 0.0
    return float(np.sqrt(252) * excess.mean() / excess.std())


def market_risk_summary(returns: pd.Series) -> dict:
    """Return a dictionary of commonly used market risk metrics."""
    return {
        "annualized_return": float(returns.mean() * 252),
        "annualized_volatility": float(returns.std() * np.sqrt(252)),
        "sharpe_ratio": sharpe_ratio(returns),
        "max_drawdown": max_drawdown(returns),
        "var_95": value_at_risk(returns, 0.95),
        "var_99": value_at_risk(returns, 0.99),
        "expected_shortfall_95": expected_shortfall(returns, 0.95),
        "expected_shortfall_99": expected_shortfall(returns, 0.99),
    }
