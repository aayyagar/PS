# Integrated Market & Credit Risk Simulation Platform

Python project for resume-ready market risk and credit risk analytics using simulation and machine learning.

## Business Goal

This project combines two major risk analytics areas:

1. **Market Risk**: estimate downside loss for a portfolio using VaR, Expected Shortfall, volatility, drawdown, and Monte Carlo simulation.
2. **Credit Risk**: predict borrower default probability using ML classification and estimate Expected Credit Loss using PD, LGD, and EAD.

## Main Features

- Historical/synthetic portfolio return generation
- Market risk metrics: volatility, Sharpe ratio, maximum drawdown, VaR, Expected Shortfall
- Monte Carlo simulation for future portfolio paths
- Credit default prediction using Logistic Regression and Random Forest
- Credit loss simulation using PD x LGD x EAD
- Baseline, high-rate, and recession stress scenarios
- Clean outputs for resume, GitHub, and interview discussion

## Project Structure

```text
market_credit_risk_platform/
├── run_project.py
├── requirements.txt
├── src/
│   ├── market_risk.py
│   ├── credit_risk.py
│   └── simulation.py
├── data/
│   └── README.md
└── outputs/
```

## How to Run

```bash
cd market_credit_risk_platform
python -m venv .venv
.venv\Scripts\activate      # Windows
pip install -r requirements.txt
python run_project.py
```

On Mac/Linux:

```bash
source .venv/bin/activate
pip install -r requirements.txt
python run_project.py
```

## Output

The script prints:

- Market risk summary
- VaR and Expected Shortfall
- Monte Carlo portfolio loss estimates
- Credit model ROC-AUC
- Credit portfolio Expected Credit Loss by scenario

## Resume Bullet

Built an integrated Market & Credit Risk Simulation Platform using Python, Pandas, NumPy, Scikit-learn, and Monte Carlo simulation to estimate VaR, Expected Shortfall, portfolio drawdown risk, borrower default probability, and expected credit loss under baseline and recession stress scenarios.

## Interview Explanation

For market risk, the project calculates portfolio returns, volatility, Sharpe ratio, maximum drawdown, VaR, and Expected Shortfall. It then applies Monte Carlo simulation to generate future portfolio paths and estimate downside loss exposure.

For credit risk, the project builds ML models to predict borrower default probability using borrower-level features such as income, loan amount, interest rate, debt-to-income ratio, and delinquency history. The default probabilities are then used with LGD and EAD assumptions to estimate Expected Credit Loss under multiple scenarios.
