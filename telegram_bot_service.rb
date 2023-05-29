# frozen_string_literal: true

require 'telegram/bot'
require 'open-uri'
require 'json'
require 'faraday'
require 'faraday_middleware'
require 'dotenv/load'
require 'pry'
require 'streamio-ffmpeg'

class TelegramBotService
  TELEGRAM_API_URL = 'https://api.telegram.org'
  YANDEX_SPEECHKIT_API_URL = 'https://stt.api.cloud.yandex.net/speech/v1/stt:recognize'
  MAX_VOICE_MESSAGE_LENGTH = 30 # seconds

  class << self
    def run
      puts 'Telegram bot is running...'
      Telegram::Bot::Client.run(token) do |bot|
        bot.listen do |message|
          process_message(bot, message) if message.voice
        end
      end
    end

    private

    def process_message(bot, message)
      if message.voice.duration > MAX_VOICE_MESSAGE_LENGTH
        bot.api.send_message(
          chat_id: message.chat.id,
          text: "Please send a voice message that is less than #{MAX_VOICE_MESSAGE_LENGTH} seconds long."
        )
      else
        process_voice_message(bot, message)
      end
    end

    def fetch_voice_file(bot, file_id)
      file_info = bot.api.get_file(file_id: file_id)
      file_path = file_info['result']['file_path']
      telegram_file_url = "#{TELEGRAM_API_URL}/file/bot#{token}/#{file_path}"

      response = Faraday.get(telegram_file_url)
      Tempfile.new(['voice', '.oga']).tap do |file|
        file.binmode
        file.write(response.body)
        file.rewind
      end
    end

    def process_voice_message(bot, message)
      file = fetch_voice_file(bot, message.voice.file_id)

      converted_file = convert_voice_message(file.path)

      response = send_for_transcoding(converted_file)

      speech_to_text_result = JSON.parse(response.body)['result']

      bot.api.send_message(chat_id: message.chat.id, text: speech_to_text_result.to_s)

      converted_file.close
    end

    def convert_voice_message(voice_file_path)
      converted_file = Tempfile.new(['converted', '.ogg'])

      movie = FFMPEG::Movie.new(voice_file_path)
      movie.transcode(converted_file.path)

      converted_file
    end

    def send_for_transcoding(converted_file)
      conn = Faraday.new(url: YANDEX_SPEECHKIT_API_URL) do |f|
        f.request :url_encoded
        f.adapter :net_http
      end

      audio = Faraday::UploadIO.new(converted_file.path, 'audio/ogg')

      conn.post do |req|
        req.headers['Authorization'] = "Bearer #{ENV['YANDEX_IAM_TOKEN']}"
        req.headers['Content-Type'] = 'audio/ogg'
        req.params['folderId'] = ENV['YANDEX_FOLDER_ID']
        req.body = audio.read
      end
    end

    def token
      @token ||= ENV['TELEGRAM_BOT_TOKEN']
    end
  end
end
