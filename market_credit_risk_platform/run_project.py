"""Run the Integrated Market & Credit Risk Simulation Platform.

This project is intentionally self-contained. It uses synthetic market and credit data so the
full pipeline can run without paid APIs or external datasets.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from src.credit_risk import assign_risk_band, generate_synthetic_credit_data, train_credit_models
from src.market_risk import calculate_returns, market_risk_summary, portfolio_returns
from src.simulation import credit_stress_scenarios, monte_carlo_loss_summary, monte_carlo_portfolio_paths


def generate_synthetic_prices(days: int = 756, seed: int = 42) -> pd.DataFrame:
    """Create synthetic daily prices for a diversified portfolio."""
    rng = np.random.default_rng(seed)
    tickers = ["SPY", "QQQ", "IWM", "JPM", "MSFT"]
    assumptions = {
        "SPY": (0.00035, 0.011),
        "QQQ": (0.00045, 0.014),
        "IWM": (0.00030, 0.016),
        "JPM": (0.00032, 0.015),
        "MSFT": (0.00050, 0.014),
    }

    prices = pd.DataFrame(index=pd.date_range(end=pd.Timestamp.today(), periods=days, freq="B"))
    for ticker in tickers:
        mean_return, volatility = assumptions[ticker]
        daily_returns = rng.normal(mean_return, volatility, days)
        prices[ticker] = 100 * np.cumprod(1 + daily_returns)
    return prices


def print_section(title: str) -> None:
    print("\n" + "=" * 80)
    print(title)
    print("=" * 80)


def main() -> None:
    print_section("MARKET RISK ANALYSIS")
    prices = generate_synthetic_prices()
    returns = calculate_returns(prices)
    weights = np.array([0.35, 0.20, 0.15, 0.15, 0.15])
    port_returns = portfolio_returns(returns, weights)
    summary = market_risk_summary(port_returns)

    for metric, value in summary.items():
        print(f"{metric:28s}: {value:.4f}")

    print_section("MONTE CARLO PORTFOLIO SIMULATION")
    current_portfolio_value = 100_000
    paths = monte_carlo_portfolio_paths(
        current_value=current_portfolio_value,
        mean_daily_return=port_returns.mean(),
        daily_volatility=port_returns.std(),
        days=252,
        simulations=10_000,
    )
    mc_summary = monte_carlo_loss_summary(paths, current_portfolio_value)
    for metric, value in mc_summary.items():
        print(f"{metric:28s}: {value:,.2f}")

    print_section("CREDIT RISK MODELING")
    credit_df = generate_synthetic_credit_data(rows=2_500)
    model_results = train_credit_models(credit_df)

    best_model_name = max(model_results, key=lambda name: model_results[name]["roc_auc"])
    best_result = model_results[best_model_name]
    print(f"Best model: {best_model_name}")
    print(f"ROC-AUC   : {best_result['roc_auc']:.4f}")
    print(f"Confusion Matrix: {best_result['confusion_matrix']}")

    avg_pd = float(np.mean(best_result["test_pd"]))
    print(f"Average predicted PD: {avg_pd:.4f}")
    print(f"Sample borrower risk band: {assign_risk_band(avg_pd)}")

    print_section("CREDIT LOSS STRESS TESTING")
    ecl_summary = credit_stress_scenarios(
        base_pd=best_result["test_pd"],
        ead=best_result["test_ead"],
        lgd=0.45,
    )
    print(ecl_summary.to_string(index=False))


if __name__ == "__main__":
    main()
