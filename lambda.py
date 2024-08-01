from fastapi import FastAPI
from eliza import eliza
# from pydantic import BaseModel

app = FastAPI()



eliza = eliza.Eliza()
eliza.load('eliza/doctor.txt')

@app.post("/")
def root(said: str):
    response = eliza.respond(said)
    return {
        "input": said,
        "response": response
    }

@app.get("/_healtz")
def healtz():
    return {"version": "0.2"}
