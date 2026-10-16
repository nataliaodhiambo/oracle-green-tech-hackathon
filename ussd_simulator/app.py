"""KilimoPesa farmer USSD/SMS service.

POST /ussd is an Africa's Talking USSD callback. Point the sandbox USSD
channel at it, or open http://localhost:5000/ for the phone mockup.

Set AT_USERNAME (e.g. "sandbox") and AT_API_KEY to also send real SMS
through Africa's Talking; otherwise SMS only goes to the mockup's inbox.
"""
import os
from datetime import datetime
from pathlib import Path

from flask import Flask, jsonify, request, send_from_directory

from ussd_menu import demo_farmers, handle_ussd

STATIC_DIR = Path(__file__).resolve().parent / "static"

app = Flask(__name__)
outbox = []  # SMS sent this run, newest last

sms_service = None
if os.environ.get("AT_USERNAME") and os.environ.get("AT_API_KEY"):
    import africastalking

    africastalking.initialize(os.environ["AT_USERNAME"], os.environ["AT_API_KEY"])
    sms_service = africastalking.SMS


def send_sms(phone, message):
    outbox.append({"to": phone, "message": message, "sent_at": datetime.now().strftime("%H:%M")})
    if sms_service:
        try:
            sms_service.send(message, [phone])
        except Exception as e:
            app.logger.warning("Africa's Talking SMS failed: %s", e)


@app.post("/ussd")
def ussd():
    phone = request.form.get("phoneNumber", "")
    text = request.form.get("text", "")
    response, sms = handle_ussd(phone, text)
    if sms:
        send_sms(phone, sms)
    return response, 200, {"Content-Type": "text/plain"}


@app.get("/sms")
def sms_inbox():
    phone = request.args.get("phone")
    return jsonify([m for m in outbox if m["to"] == phone])


@app.get("/farmers")
def farmers():
    return jsonify(demo_farmers())


@app.get("/")
def phone_mockup():
    return send_from_directory(STATIC_DIR, "phone.html")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)), debug=True)
