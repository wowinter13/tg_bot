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
  # I am not proud of this,
  # but for some reason yandex responds with an error if the voice message is longer than approx. 7 seconds
  # (even though the documentation says the limit is 30 seconds)
  MAX_VOICE_MESSAGE_LENGTH = 7 # seconds
  MAX_VOICE_ERROR_MESSAGE = "Please send a voice message that is less than #{MAX_VOICE_MESSAGE_LENGTH} seconds long."

  class << self
    def run
      puts 'Telegram bot is running...'
      Telegram::Bot::Client.run(token) do |bot|
        bot.listen do |message|
          process_voice_message(bot, message) if message.voice
        end
      end
    end

    private

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
      converted_files = convert_and_split_voice_message(file.path)
    
      threads = []
      responses = {}
      mutex = Mutex.new
      
      converted_files.each_with_index do |converted_file, index|
        threads << Thread.new do
          response = send_for_transcoding(converted_file)
          parsed_response = JSON.parse(response.body)
    
          mutex.synchronize do
            if parsed_response['error_message']
              responses[index] = parsed_response['error_message']
            else
              responses[index] = parsed_response['result'].to_s
            end
          end
    
          File.delete(converted_file) if File.exist?(converted_file)
        end
      end
    
      threads.each(&:join)

      sorted_responses = responses.sort_by { |index, _| index }.map { |_, text| text }
    
      if sorted_responses.any? { |response| response.include?('error_message') }
        process_error_message(bot, message, sorted_responses.join('. '))
      else
        bot.api.send_message(chat_id: message.chat.id, text: sorted_responses.join('. '))
      end
    end
  
    def convert_and_split_voice_message(voice_file_path)
      movie = FFMPEG::Movie.new(voice_file_path)
      duration = movie.duration
      file_counter = 0
      converted_files = []

      while file_counter * MAX_VOICE_MESSAGE_LENGTH < duration do
        start_time = file_counter * MAX_VOICE_MESSAGE_LENGTH
        output_file_path = "split_#{file_counter}.ogg"
        command = "ffmpeg -i #{voice_file_path} -ss #{start_time} -t #{MAX_VOICE_MESSAGE_LENGTH} #{output_file_path}"
        system(command)
        
        converted_files << File.open(output_file_path)
        file_counter += 1
      end
  
      converted_files
    end

    def process_error_message(bot, message, error_text)
      bot.api.send_message(
        chat_id: message.chat.id,
        text: error_text
      )
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
