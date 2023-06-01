# frozen_string_literal: true

require 'rspec'
require 'telegram/bot'
require 'tempfile'
require 'dotenv/load'

RSpec.configure do |config|
  config.before(:suite) do
    Dotenv.load('.env.test')
  end
end

require 'webmock/rspec'
require 'json'

require_relative 'telegram_bot_service'

RSpec.describe TelegramBotService do
  let(:bot_token) { 'your_bot_token' }
  let(:file_id) { 'your_file_id' }
  let(:file_path) { 'path/to/telegram_file.oga' }
  let(:telegram_file_url) { "https://api.telegram.org/file/bot#{bot_token}/#{file_path}" }
  let(:file) { File.open('fixtures/telegram_file.oga') }
  let(:yandex_response) { OpenStruct.new(body: '{"result": "speech_to_text_result"}') }

  subject { described_class }

  before do
    WebMock.disable_net_connect!
    allow(Telegram::Bot::Api).to receive(:new).and_call_original
  end

  after do
    WebMock.allow_net_connect!
  end

  describe '.run' do
    let(:bot) { instance_double(Telegram::Bot::Client) }
    let(:message) { instance_double(Telegram::Bot::Types::Message, voice: voice_message, chat: chat) }
    let(:voice_message) { instance_double(Telegram::Bot::Types::Voice, file_id: file_id, duration: 20) }
    let(:chat) { instance_double(Telegram::Bot::Types::Chat, id: 123) }
    let(:api) { Telegram::Bot::Api.new(bot_token) }

    before do
      allow(Telegram::Bot::Client).to receive(:run).and_yield(bot)
      allow(bot).to receive(:listen).and_yield(message)
      allow(bot).to receive(:api).and_return(api)
      allow(subject).to receive(:fetch_voice_file).and_return(file)
      allow(subject).to receive(:send_for_transcoding).and_return(yandex_response)
    end

    it 'processes the voice message and sends back the result' do
      expect(subject).to receive(:fetch_voice_file).with(bot, file_id).and_return(file)
      expect(subject).to receive(:send_for_transcoding).with(instance_of(File)).and_return(yandex_response)
      expect(api).to receive(:send_message).with(chat_id: 123, text: 'speech_to_text_result')

      thread = Thread.new do
        TelegramBotService.run
      end

      sleep(1)
      Thread.kill(thread)

      Process.kill(0, Process.pid)
    end
  end
end
