# -*- coding: utf-8 -*-

require 'selenium-webdriver'

module Plugin::Mikuttdeck

  BaseError = Class.new(StandardError)
  Error = Class.new(BaseError)
  StateError = Class.new(BaseError)

  # Selenium::WebDriver のラッパークラス。メソッドの呼び出しは Deferred される
  class DriverProxy

    attr_reader :thread

    def initialize(browser, option = {}, url)
      @thread = SerialThreadGroup.new(deferred: Deferred)

      @proc = Thread.new do
        @driver = Selenium::WebDriver.for browser, option
        @driver.get(url)
        # TweetDeckが読み込み終わるまで待つ
        # TODO: ちゃんとする
        sleep 4
        @driver
      end
    end

    def destroy(*args, &blk)
      thread.new do
        begin
          @proc&.join
        ensure
          break if @destroyed
          @destroyed = true
          @driver&.quit
          @driver = nil
        end
      end
    end

    def at_exit
      @driver&.quit unless @destroyed
    end
  
    def method_missing(name, *args, &blk)
      thread.new do
        raise StateError if @destroyed
        if @proc
          begin
            @proc.join
          rescue => e
            @driver&.quit
            @destroyed = true
            raise Error, Plugin[:mikuttdeck]._('mikuttdeck: ブラウザの起動に失敗しました。')
          end
          @proc = nil
        end
        @driver.__send__(name, *args, &blk)
      end
    end

    def respond_to_missing?(name, include_private)
      @driver.respond_to?(name, include_private)
    end
  end

  class Deck

    def initialize(browser, option = {})
      @driver = DriverProxy.new(browser, option, 'https://tweetdeck.twitter.com')
      @js = {}
      @status = :initialized
    end

    def start
      Deferred.new do
        raise StateError unless @status == :initialized
        @status = :starting
        +@driver.find_element(:id, 'container').trap {|e|
          case e
          when Selenium::WebDriver::Error::NoSuchElementError
            Deferred.fail(Error.new('mikuttdeck: TweetDeckにログインしていないようです。'))
          else
            Deferred.fail(e)
          end
        }
        columns = (+get_columns).select{|c| c.type == :home_timeline }
        if columns.empty?
          raise Error, Plugin[:mikuttdeck]._(
            'mikuttdeck: TweetDeckでつかえるカラムが開かれてないようです。' \
              'mikutterにログインしているのと同じアカウントでログインし、Homeカラムを開いてください。'
          )
        end
        @columns = columns
        @status = :running
        refresh
      end
    end

    def refresh
      return unless @status == :running
      fetch
      Reserver.new(4) do
        Deferred.new do
          refresh
        end
      end
    end

    def fetch
      Deferred.new do
        @columns.each do |column|
          ids = +@driver.execute_script(
            @js[column.type] ||=
              file_get_contents(File.expand_path(File.join(File.dirname(__FILE__), "#{ column.type }.js"))),
            column.element,
            column.latest
          )
          column.latest = ids.first
          messages = +((column.service.twitter/'statuses/lookup').messages(id: ids.join(',')))
          Plugin.call(:update, column.service, messages)
          Plugin.call(:mention, column.service, messages.select{ |m| m.to_me? })
          Plugin.call(:mypost, column.service, messages.select{ |m| m.from_me? })
          messages
        end
      end
    end

    def destroy
      @driver.destroy unless @status == :destroyed
      @status = :destroyed
    end
  
    def at_exit
      @driver.at_exit
    end
  
    private def get_columns
      Deferred.new do
        (+@driver.find_elements(:css,
          '#column-navigator > div.js-column-nav-list > ul.js-int-scroller > li.column-nav-item'
        )).map do |e|
          data_column = +@driver.thread.new do e.attribute('data-column') end
          element = +@driver.find_element(:css,
            "#container > div.app-columns > section.column[data-column=#{ data_column }] > div.column-holder" \
              " > div.column-panel > div.column-content > div.column-scroller > div.chirp-container"
          )
          type = (+@driver.thread.new do
            e.find_element(:css, 'a.column-nav-link > div.js-column-title > span.column-heading')
          end).text
          type = case type
            when 'Home'
              :home_timeline
            when 'Notifications'
              :notifications
            else
              type
            end
          screen_name = (+@driver.thread.new do
            e.find_element(
              :css, 'a.column-nav-link > div.js-column-title > span.attribution'
            )
          end).text.delete_prefix('@')
          Column.new(element, type, screen_name)
        end.select {|c| c.service }
      end
    end
  end

  class Deck::Column < Struct.new(:element, :type, :service, :latest)
    class << self
      def new(element, type, screen_name)
        service = Service.instances.find do |s|
          s.user_obj.idname == screen_name
        end
        super(element, type, service, nil)
      end
    end
  end
end

Plugin.create(:mikuttdeck) do

  def start
    Deferred.new do
      if UserConfig[:mikuttdeck_browser].empty?
        raise Plugin::Mikuttdeck::Error,
          'mikuttdeck: ブラウザが設定されていません。設定ダイアログでブラウザを設定して、その後mikuttdeckを有効にし直してください。'
      end
      @deck = Plugin::Mikuttdeck::Deck.new(
        UserConfig[:mikuttdeck_browser].downcase.to_sym,
        UserConfig[:mikuttdeck_selenium_option] || {}
      )
      @deck.start
    end.trap {|e|
      @deck&.destroy
      @deck = nil
      case e
      when Plugin::Mikuttdeck::Error
        activity :system, e.message
      else
        Deferred.fail(e)
      end
    }
    end

  def stop
    if @deck
      @deck.destroy
      @deck = nil
    end
  end

  settings(_('mikuttdeck')) do
    boolean(_('mikuttdeckを有効にする'), :mikuttdeck_enable)
    input(_('ブラウザ'), :mikuttdeck_browser)
  end

  on_userconfig_modify do |key, newval|
    if key == :mikuttdeck_enable
      if newval then start else stop end
    end
  end

  at_exit do
    @deck&.at_exit
  end

  start if UserConfig[:mikuttdeck_enable]
end
