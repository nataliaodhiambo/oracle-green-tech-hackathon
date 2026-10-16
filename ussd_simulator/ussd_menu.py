from datetime import date

from scoring import (
    DISCOUNT_THRESHOLD,
    EXAMPLE_LOAN_KES,
    GREEN_RATE,
    PAYOUT_THRESHOLD,
    STANDARD_RATE,
    interest_rate,
    load_plots,
    ranked_actions,
)

PLOTS = load_plots()


# Demo phone numbers: PLOT_003 <-> +254711000003
def phone_for_plot(plot_id):
    return f"+254711000{plot_id.split('_')[1]}"


def plot_for_phone(phone):
    plot_id = f"PLOT_{phone[-3:]}" if phone.startswith("+254711000") else None
    return plot_id if plot_id in PLOTS else None


def _month(record):
    return date.fromisoformat(record["assessment_date"]).strftime("%b")


def _status(crs):
    if crs >= DISCOUNT_THRESHOLD:
        return "Green discount"
    if crs < PAYOUT_THRESHOLD:
        return "Drought relief"
    return "Standard rate"


def score_screen(history):
    latest = history[-1]
    trend = " > ".join(f"{_month(r)} {r['crs_score']}" for r in history)
    lines = [
        f"Green Score ({_month(latest)}): {latest['crs_score']}/100",
        f"Status: {_status(latest['crs_score'])}",
        f"Trend: {trend}",
    ]
    if latest["crs_score"] < PAYOUT_THRESHOLD:
        lines.append("Drought relief payout triggered.")
    return "\n".join(lines)


def actions_screen(history):
    latest = history[-1]
    top = ranked_actions(latest)[:3]
    if not top:
        return "Your plot is already at top resilience. Keep it up!"

    lines = ["Raise your score:"]
    lines += [f"{i}. {a['name']} +{a['gain']}" for i, a in enumerate(top, 1)]
    total = round(sum(a["gain"] for a in top), 1)
    projected = min(100.0, round(latest["crs_score"] + total, 1))
    lines.append(f"All 3: {latest['crs_score']} -> {projected}")
    return "\n".join(lines)


def rate_screen(history):
    crs = history[-1]["crs_score"]
    saving = round(EXAMPLE_LOAN_KES * (STANDARD_RATE - GREEN_RATE) / 100)
    if interest_rate(crs) == GREEN_RATE:
        return (
            f"Your rate: {GREEN_RATE}% (Green discount)\n"
            f"Saves KES {saving:,}/yr on a KES {EXAMPLE_LOAN_KES:,} loan vs {STANDARD_RATE}%"
        )
    gap = round(DISCOUNT_THRESHOLD - crs, 1)
    lines = [
        f"Your rate: {STANDARD_RATE}%",
        f"Reach {DISCOUNT_THRESHOLD:g} (+{gap} pts) for {GREEN_RATE}%",
        f"Saves KES {saving:,}/yr on KES {EXAMPLE_LOAN_KES:,}",
    ]
    if crs < PAYOUT_THRESHOLD:
        lines.append("Drought relief payout: triggered")
    return "\n".join(lines)


def sms_summary(history):
    latest = history[-1]
    crs = latest["crs_score"]
    top = ranked_actions(latest)[:1]
    tip = f"{top[0]['name']} (+{top[0]['gain']} pts)" if top else "keep current practices"
    return (
        f"KilimoPesa: {latest['farmer_name']}, Green Score {crs}/100 ({_status(crs)}). "
        f"Loan rate {interest_rate(crs)}%. Tip: {tip}."
    )


MAIN_MENU = (
    "1. My Green Score\n"
    "2. How to raise my score\n"
    "3. My loan interest rate\n"
    "4. SMS me my summary"
)

SCREENS = {"1": score_screen, "2": actions_screen, "3": rate_screen}


def handle_ussd(phone, text):
    """Return (response, sms) for an Africa's Talking USSD request.

    `text` is every input in the session joined by '*', e.g. "1*0*3".
    `sms` is a message to send to the farmer, or None.
    """
    steps = text.split("*") if text else []

    plot_id = plot_for_phone(phone)
    if plot_id is None:
        # Unregistered number: ask for the plot number first
        if not steps:
            return "CON Welcome to KilimoPesa\nEnter your Plot number (e.g. 3):", None
        entered = steps.pop(0)
        plot_id = f"PLOT_{int(entered):03d}" if entered.isdigit() else None
        if plot_id not in PLOTS:
            return "END Plot not found. Please dial again.", None

    history = PLOTS[plot_id]

    # Walk the inputs; "0" on a sub-screen goes back to the main menu
    screen = None
    for step in steps:
        if screen is None:
            screen = step
        elif step == "0":
            screen = None
        else:
            return "END Invalid choice. Please dial again.", None

    if screen is None:
        first_name = history[-1]["farmer_name"].split()[0]
        return f"CON KilimoPesa - Habari {first_name}\n{MAIN_MENU}", None
    if screen == "4":
        return f"END Summary sent by SMS to {phone}. Asante!", sms_summary(history)
    if screen in SCREENS:
        return f"CON {SCREENS[screen](history)}\n0. Back", None
    return "END Invalid choice. Please dial again.", None


def demo_farmers():
    return [
        {
            "phone": phone_for_plot(plot_id),
            "plot_id": plot_id,
            "farmer_name": history[-1]["farmer_name"],
            "crs_score": history[-1]["crs_score"],
        }
        for plot_id, history in sorted(PLOTS.items())
    ]
