# Data Folder

This project currently uses synthetic data generated inside `run_project.py` and `src/credit_risk.py`.

You can later replace the synthetic inputs with:

## Market Risk Data

- Historical equity prices
- ETF prices
- Portfolio holdings and weights
- Benchmark index prices

Suggested columns:

```text
Date, Ticker, Close, Volume
```

## Credit Risk Data

- Borrower income
- Loan amount
- Interest rate
- Debt-to-income ratio
- Delinquencies
- Credit history length
- Utilization ratio
- Default flag

Suggested columns:

```text
annual_income, loan_amount, interest_rate, debt_to_income, delinquencies, credit_history_years, utilization, default
```

Keep raw data out of public GitHub if it contains private, personal, borrower, or employer information.
