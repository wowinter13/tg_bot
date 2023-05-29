
### How to use

`@YandexVoiceTest_bot` – telegram bot

This solution is primarly intented to be used by the server directly, so in case you want to test it locally – you just need to provide required env variables to a `.env` file.


**To run locally:**

```bash
ruby bot.rb
```


**Additional requirements:**

- ffmpeg 


### Remarks

1. Sorry, initially I had thought to use Rails, but after I analyzed the task overall – I decided to just run `bot.rb` as a daemon using `Procfile` on `Heroku`.

2. The solution is simplified a lot. If this code was needed to be implemented in an existing web app, I'd add/change these things:

    - **Async usage**
      Right now we just wait for the response from Yandex, but possibly in case of HL we need to limit the simultaneous number of operations (i.e. https://cloud.yandex.com/en/docs/speechkit/concepts/limits – 20/40RPS)
    - **Add better error handling**
      It would be beneficial to include error handling to handle potential exceptions that may occur during API requests or other operations.
      At least, we could use retries, just in case Yandex responded with non-200 http codes.
    - **Add better logging**
    - **Modularity**
      If we plan to extend the functionality of the bot, we could break down the code into smaller, more focused classes.



### Do what you must...I will watch you.


<p align="center">
<img width="300" height="500" src="https://static.wikia.nocookie.net/elderscrolls/images/b/ba/Imperial_Prison_Guard.png/revision/latest?cb=20131214131751">
</p>
