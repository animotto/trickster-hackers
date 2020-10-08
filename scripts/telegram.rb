class Telegram < Sandbox::Script
  DATA_DIR = "#{Sandbox::ContextScript::SCRIPTS_DIR}/telegram"
  TOKEN_VAR = "telegram-token"
  SLEEP_TIME = 10
  
  class API
    HOST = "api.telegram.org"
    PORT = 443

    def initialize(token)
      @token = token
      @client = Net::HTTP.new(HOST, PORT)
      @client.use_ssl = (PORT == 443)
    end

    def getMe
      request("getMe")
    end

    def getUpdates(offset = 0)
      request(
        "getUpdates",
        {
          "offset" => offset,
        }
      )
    end

    def sendMessage(chatId, text, parseMode = "HTML")
      request(
        "sendMessage",
        {
          "chat_id" => chatId,
          "text" => text,
          "parse_mode" => parseMode,
        }
      )
    end

    private

    def request(method, params = {})
      uri = "/bot#{@token}/#{method}"
      uri += "?" + encodeURI(params) unless params.empty?
      begin
        response = @client.get(uri)
      rescue => e
        raise APIError.new("HTTP request", e.message)
      end
      raise APIError.new("HTTP request", "#{response.code} #{response.message}") unless response.instance_of?(Net::HTTPOK)
      begin
        data = JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise APIError.new("API parse", e.message)
      end
      raise APIError.new("API", data["description"]) unless data["ok"]
      raise APIError.new("API", "No result") if data["result"].nil?
      return data["result"]
    end

    def encodeURI(data)
      params = Array.new
      data.each do |k, v|
        params.push(
          [
            k,
            URI.encode_www_form_component(v).gsub("+", "%20"),
          ].join("=")
        )
      end
      return params.join("&")
    end
  end

  class APIError < StandardError
    def initialize(message, description = nil)
      @message = message
      @description = description
    end

    def to_s
      msg = @message
      msg += ": #{@description}" unless @description.nil?
      return msg
    end
  end

  def initialize(game, shell, logger, args)
    super
    Dir.mkdir(DATA_DIR) unless Dir.exist?(DATA_DIR)
    @api = API.new(@game.config[TOKEN_VAR])
  end

  def load
    file = "#{DATA_DIR}/main.conf"
    @config = Sandbox::Config.new(file)
    begin
      @config.load
    rescue JSON::ParserError => e
      @logger.error("Main config has invalid format (#{e})")
      return false
    rescue => e
      @config.merge!({
        "relays" => {},
      })
    end
    return true
  end

  def save
    begin
      @config.save
    rescue => e
      @logger.error("Can't save main config (#{e})")
    end
  end

  def admin(line)
    words = line.split(/\s+/)
    return if words.empty?
    case words[0]
      when "help", "?"
        return "Commands: me | relay <add|del> <room> <channel>"

      when "me"
        return "Me: " + @api.getMe.map {|k, v| "#{k}: #{v}"}.join(", ")

      when "relay"
        case words[1]
          when "add"
            room = words[2]
            channel = words[3]
            return "Specify room ID and channel name" if room.nil? || channel.nil?
            return "Relay for room #{room} already exists" if @config["relays"].key?(room)
            @config["relays"][room] = {
              "channel" => channel,
            }
            @config.save
            return "Relay for room #{room} added"

          when "del"
            room = words[2]
            return "Specify room ID" if room.nil?
            return "Relay for room #{room} doesn't exist" unless @config["relays"].key?(room)
            @config["relays"].delete(room)
            @config.save
            return "Relay for room #{room} deleted"

          else
            return "No relays" if @config["relays"].empty?
            relays = Array.new
            @config["relays"].each do |room, relay|
              relays.push("#{room} -> #{relay["channel"]}")
            end
            return "Relays: " + relays.join(", ")
        end

      else
        return "Unrecognized command #{words[0]}"
    end
  end

  def main
    if @game.config[TOKEN_VAR].nil? || @game.config[TOKEN_VAR].empty?
      @logger.error("No telegram token")
      return
    end

    return unless load
    chat = Hash.new

    @config["relays"].each do |room, relay|
      chat[room] = @game.getChat(room)
      begin
        chat[room].read
      rescue Trickster::Hackers::RequestError => e
        @logger.error("Chat read (#{e})")
        return
      end
      @logger.log("Relay chat room #{room} to channel #{relay["channel"]}")
    end

    loop do
      sleep(SLEEP_TIME)

      @config["relays"].each do |room, relay|
        begin
          messages = chat[room].read
        rescue Trickster::Hackers::RequestError => e
          @logger.error("Chat read (#{e})")
          next
        end

        messages.each do |message|
          msg = message.message.clone
          msg.gsub!(/\[([biusc]|sup|sub|[\da-f]{6})\]/i, "")
          msg = "<b>#{message.nick}:</b> #{msg}"
          begin
            @api.sendMessage(relay["channel"], msg)
          rescue APIError => e
            @logger.error("Send message error, from chat room #{room} to channel #{relay["channel"]} (#{e})")
          end
        end
      end
    end
  end
end

