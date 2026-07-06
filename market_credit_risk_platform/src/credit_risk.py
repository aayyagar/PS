"""Credit risk model training and evaluation."""

from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler


def generate_synthetic_credit_data(rows: int = 2_000, seed: int = 42) -> pd.DataFrame:
    """Create a realistic borrower-level dataset for project demonstration."""
    rng = np.random.default_rng(seed)

    annual_income = rng.normal(75_000, 25_000, rows).clip(25_000, 200_000)
    loan_amount = rng.normal(18_000, 8_000, rows).clip(2_000, 60_000)
    interest_rate = rng.normal(0.11, 0.04, rows).clip(0.04, 0.29)
    dti = rng.normal(0.28, 0.12, rows).clip(0.02, 0.70)
    delinquencies = rng.poisson(0.35, rows).clip(0, 5)
    credit_history_years = rng.normal(8, 4, rows).clip(1, 30)
    utilization = rng.normal(0.45, 0.22, rows).clip(0.02, 0.99)

    risk_score = (
        -3.0
        + 4.0 * dti
        + 3.5 * interest_rate
        + 0.45 * delinquencies
        + 1.5 * utilization
        + 0.000015 * loan_amount
        - 0.000012 * annual_income
        - 0.04 * credit_history_years
    )
    pd_default = 1 / (1 + np.exp(-risk_score))
    default = rng.binomial(1, pd_default)

    return pd.DataFrame(
        {
            "annual_income": annual_income,
            "loan_amount": loan_amount,
            "interest_rate": interest_rate,
            "debt_to_income": dti,
            "delinquencies": delinquencies,
            "credit_history_years": credit_history_years,
            "utilization": utilization,
            "default": default,
        }
    )


def train_credit_models(df: pd.DataFrame) -> dict:
    """Train baseline credit default models and return evaluation results."""
    features = [
        "annual_income",
        "loan_amount",
        "interest_rate",
        "debt_to_income",
        "delinquencies",
        "credit_history_years",
        "utilization",
    ]
    X = df[features]
    y = df["default"]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.25, random_state=42, stratify=y
    )

    logistic_model = Pipeline(
        steps=[
            ("scaler", StandardScaler()),
            ("model", LogisticRegression(max_iter=1_000)),
        ]
    )
    random_forest = RandomForestClassifier(
        n_estimators=250,
        max_depth=6,
        random_state=42,
        class_weight="balanced",
    )

    models = {
        "logistic_regression": logistic_model,
        "random_forest": random_forest,
    }

    results = {}
    for name, model in models.items():
        model.fit(X_train, y_train)
        default_probability = model.predict_proba(X_test)[:, 1]
        predictions = (default_probability >= 0.50).astype(int)
        results[name] = {
            "model": model,
            "roc_auc": float(roc_auc_score(y_test, default_probability)),
            "confusion_matrix": confusion_matrix(y_test, predictions).tolist(),
            "classification_report": classification_report(y_test, predictions, output_dict=True),
            "test_pd": default_probability,
            "test_ead": X_test["loan_amount"].to_numpy(),
        }

    return results


def assign_risk_band(pd_value: float) -> str:
    """Convert probability of default into an interpretable risk band."""
    if pd_value < 0.10:
        return "Low"
    if pd_value < 0.25:
        return "Medium"
    if pd_value < 0.45:
        return "High"
    return "Very High"
