# coding: utf-8
require "rss"

class Chatbot < Sandbox::Script
  DATA_DIR ||= "#{Sandbox::ContextScript::SCRIPTS_DIR}/chatbot"
  SLEEP_TIME ||= 10
  FLOOD_TIME ||= 15

  attr_reader :DATA_DIR
  attr_accessor :commands, :game, :shell,
                :room, :users, :userTimers
  
  def initialize(game, shell, args)
    super(game, shell, args)
    Dir.mkdir(DATA_DIR) unless Dir.exist?(DATA_DIR)
    @commands = {
      "!помощь" => [CmdHelp.new(self)],
      "!формат" => [CmdFormat.new(self)],
      "!считалочка" => [CmdCounting.new(self)],
      "!рулетка" => [CmdRoulette.new(self)],
      "!печенька" => [CmdCookie.new(self)],
      "!бац" => [CmdClick.new(self)],
      "!топ" => [CmdTop.new(self)],
      "!лента" => [CmdLenta.new(self)],
      "!хабр" => [CmdHabr.new(self)],
      "!лор" => [CmdLor.new(self)],
      "!баш" => [CmdBash.new(self)],
      "!фраза" => [CmdPhrase.new(self)],
      "!анекдот" => [CmdJoke.new(self)],
      "!курс" => [CmdCurrency.new(self)],
      "!привет" => [CmdHello.new(self)],
      "!путин" => [CmdPutin.new(self), true],
    }
    @room = args[0]
    @users = Hash.new
    @userTimers = Hash.new
    @last = String.new
  end
  
  def main
    if @room.nil?
      @shell.log("Specify room ID", :script)
      return
    end

    @room = @room.to_i
    @shell.log("The bot listens room #{@room}", :script)
    loop do
      sleep(SLEEP_TIME)
      next unless data = @game.cmdChatDisplay(@room, @last)
      data = @game.normalizeData(data)
      data.force_encoding("utf-8")
      records = data.split(";").reverse
      records.each_index do |i|
        fields = records[i].split(",")
        nick = fields[1]
        cmd = fields[2].downcase
        id = fields[3]
        @users[id] = nick unless id.to_i == @game.config["id"]
        if @last.empty?
          if i == records.length - 1
            @last = fields[0]
            break
          end
          next
        end
        
        @last = fields[0]
        next if @userTimers.key?(id) && Time.now - @userTimers[id] <= FLOOD_TIME
        next unless @commands.key?(cmd)
        @commands[cmd][0].exec(nick, cmd, id)
        @userTimers[id] = Time.now
      end
    end
  end
end

class CmdBase
  def initialize(script)
    @script = script
  end

  def exec(nick, cmd, id)
  end

  def rss(host, port, url)
    http = Net::HTTP.new(host, port)
    http.use_ssl = true if port == 443
    response = http.get(url)
    return false unless response.code == "200"
    return RSS::Parser.parse(response.body, false)
  end
end

class CmdHelp < CmdBase
  def exec(nick, cmd, id)
    msg = "[b][77a9ff]ВОТ ЧТО Я УМЕЮ: "
    @script.commands.each do |k, v|
      msg += "#{k} " unless v[1]
    end
    @script.game.cmdChatSend(@script.room, msg)
  end
end

class CmdFormat < CmdBase
  def exec(nick, cmd, id)
    msg = "[b][ffffff][ b ] - жирный, [ i ] - курсив, [ u ] - подчеркнутый, [ s ] - зачёркнутый, [rrggbb] - цвет в HEX формате"
    @script.game.cmdChatSend(@script.room, msg)
  end
end

class CmdCounting < CmdBase
  def exec(nick, cmd, id)
    msg = "[b][00ff00]ШИШЕЛ-МЫШЕЛ, СЕЛ НА КРЫШКУ, ШИШЕЛ-МЫШЕЛ, ВЗЯЛ И ВЫШЕЛ [ffff00]#{@script.users[@script.users.keys.sample]}!"
    @script.game.cmdChatSend(@script.room, msg)
  end
end

class CmdRoulette < CmdBase
  def exec(nick, cmd, id)
    if rand(1..6) == 3
      msg = "[b][ffff00]#{nick} [00ff00] ПИФ ПАФ! ТЫ УБИТ!"
    else
      msg = "[b][ffff00]#{nick} [00ff00]В ЭТОТ РАЗ ТЕБЕ ПОВЕЗЛО!"
    end
    @script.game.cmdChatSend(@script.room, msg)
  end
end

class CmdCookie < CmdBase
  def exec(nick, cmd, id)
    if rand(0..1) == 0
      msg = "[00ff00]ТЫ МОЛОДЕЦ [ffff00]#{nick}[00ff00]! ВОТ ТВОЯ ПЕЧЕНЬКА!"
    else
      msg = "[00ff00]ФИГУШКИ ТЕБЕ [ffff00]#{nick}[00ff00], А НЕ ПЕЧЕНЬКА!"
    end
    @script.game.cmdChatSend(@script.room, msg)
  end
end

class CmdHello < CmdBase
  def exec(nick, cmd, id)
      msg = "[6aab7f]ПРИВЕТ [ff35a0]#{nick}[6aab7f]!"
    @script.game.cmdChatSend(@script.room, msg)
  end
end

class CmdClick < CmdBase
  DATA_FILE ||= "#{Chatbot::DATA_DIR}/click.json"
  WHO ||= [
    "ХАКЕРЬЁ СБАЦАЛО",
    "ХАКЕРЮГИ СБАЦАЛИ",
  ]

  attr_reader :DATA_FILE
  
  def initialize(script)
    super(script)
    @counter = 0
    @users = Hash.new
    File.write(DATA_FILE, JSON.generate([@counter, @users])) unless File.file?(DATA_FILE)
  end

  def exec(nick, cmd, id)
    begin
      @counter, @users = JSON.parse(File.read(DATA_FILE))
    rescue
    end
    @counter += 1
    @users[id] = [nick, 0] unless @users.key?(id)
    @users[id] = [nick, @users[id][1] + 1]
    msg = "[b][ff3500]#{WHO.sample} УЖЕ [ff9ea1]#{@counter} [ff3500]РАЗ! ПРИСОЕДИНЯЙСЯ!"
    @script.game.cmdChatSend(@script.room, msg)
    File.write(
      DATA_FILE,
      JSON.generate([@counter, @users]),
    )
  end
end

class CmdTop < CmdBase
  def exec(nick, cmd, id)
    counter = 0
    users = Hash.new
    begin
      counter, users = JSON.parse(File.read(CmdClick::DATA_FILE))
    rescue
    end
    if users.nil? || users.empty?
      msg = "[b][7aff38]В ДАННЫЙ МОМЕНТ ХАКЕРЮГ НЕТ, ТЫ МОЖЕШЬ СТАТЬ ПЕРВЫМ!"
    else
      c = Array.new
      users.each do |k, v|
        if c.empty?
          c = v
          next
        end
        c = v if v[1] > c[1]
      end
      msg = "[b][ff312a]#{c[0]}[7aff38] ХАКЕРЮГА НОМЕР ОДИН! НАБАЦАЛ [ff312a]#{c[1]}[7aff38] РАЗ!"
    end
    @script.game.cmdChatSend(@script.room, msg)
  end
end

class CmdLenta < CmdBase
  def exec(nick, cmd, id)
    if feed = rss("lenta.ru", 443, "/rss/news")
      msg = "[b][39fe12]" + feed.items.sample.title
      @script.game.cmdChatSend(@script.room, msg)
    end
  end
end

class CmdHabr < CmdBase
  def exec(nick, cmd, id)
    if feed = rss("habr.com", 443, "/ru/rss/news/")
      msg = "[b][7aff51]" + feed.items.sample.title
      @script.game.cmdChatSend(@script.room, msg)
    end
  end
end

class CmdLor < CmdBase
  def exec(nick, cmd, id)
    if feed = rss("www.linux.org.ru", 443, "/section-rss.jsp?section=1")
      msg = "[b][81f5d0]" + feed.items.sample.title
      @script.game.cmdChatSend(@script.room, msg)
    end
  end
end

class CmdBash < CmdBase
  def exec(nick, cmd, id)
    if feed = rss("bash.im", 443, "/rss/")
      data = feed.items.sample.description
      data.gsub!(/<.*>/, " ")
      msg = "[b][d5e340]" + data
      @script.game.cmdChatSend(@script.room, msg)
    end
  end
end

class CmdPhrase < CmdBase
  def exec(nick, cmd, id)
    if feed = rss("www.aphorism.ru", 443, "/rss/aphorism-new.rss")
      msg = "[b][a09561]" + feed.items.sample.description
      @script.game.cmdChatSend(@script.room, msg)
    end
  end
end

class CmdJoke < CmdBase
  def exec(nick, cmd, id)
    if feed = rss("www.anekdot.ru", 443, "/rss/export_bestday.xml")
      data = feed.items.sample.description
      data.gsub!(/<.*>/, "")
      msg = "[b][38bfbe]" + data
      @script.game.cmdChatSend(@script.room, msg)
    end
  end
end

class CmdCurrency < CmdBase
  def exec(nick, cmd, id)
    if feed = rss("currr.ru", 80, "/rss/")
      data = feed.items[-1].description
      data.gsub!(/<.*>/, "")
      data.gsub!(/\s+/, " ")
      msg = "[b][8f4a6d]" + data
      @script.game.cmdChatSend(@script.room, msg)
    end
  end
end

class CmdPutin < CmdBase
  def exec(nick, cmd, id)
    msg = "[s]Путин думает о нас! Путин заботится о нас! До здравствует Путин!"
    @script.game.cmdChatSend(@script.room, msg)
  end
end
