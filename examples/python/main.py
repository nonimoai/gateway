"""Send a chat request through Nonimo Gateway with the OpenAI Python SDK."""
import os

from openai import OpenAI

client = OpenAI(
    base_url=os.environ["GATEWAY_URL"],  # for example https://gateway.your-company.com/v1
    api_key=os.environ["GATEWAY_ACCESS_KEY"],  # the Gateway access key, not your provider key
)

response = client.chat.completions.create(
    model=os.environ.get("MODEL", "gpt-4o-mini"),
    messages=[
        {
            "role": "user",
            "content": "Write a short reply to Jane Citizen (jane.citizen@example.com).",
        }
    ],
)

print(response.choices[0].message.content)
