// Send a chat request through Nonimo Gateway with the OpenAI Node SDK.
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: process.env.GATEWAY_URL, // for example https://gateway.your-company.com/v1
  apiKey: process.env.GATEWAY_ACCESS_KEY, // the Gateway access key, not your provider key
});

const response = await client.chat.completions.create({
  model: process.env.MODEL ?? "gpt-4o-mini",
  messages: [
    {
      role: "user",
      content: "Write a short reply to Jane Citizen (jane.citizen@example.com).",
    },
  ],
});

console.log(response.choices[0].message.content);
