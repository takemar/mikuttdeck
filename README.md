# なんこれ

黒魔術を使ってUserStream亡き後のmikutterにリアルタイムっぽい更新を提供するプラグインです。

(ブラウザ自動化ツール[Selenium](https://www.seleniumhq.org/)でTweetDeckを起動して、データを吸い上げてmikutterに提供します。あまり褒められたアレではないので、こっそり使ってください。)

# 使い方

## プラグイン本体のインストール

```
$ mkdir -p ~/.mikutter/plugin; git clone https://github.com/takemar/mikuttdeck.git ~/.mikutter/plugin/mikuttdeck
```

## bundle

追加のgemが必要です。`mikutter.rb`の存在するディレクトリで`bundle install`してください。bundleでない方は`gem install selenium-webdriver`です。

## ブラウザの準備

Seleniumで使えるようにブラウザを準備します。Google Chromeの場合は[ChromeDriver](http://chromedriver.chromium.org/downloads)、Firefoxの場合は[geckodriver](https://github.com/mozilla/geckodriver)が必要です。[Seleniumのドキュメント](https://www.seleniumhq.org/docs/03_webdriver.jsp#selenium-webdriver-s-drivers)も参考にしてください。

## 有効にする

mikutterを起動すると、設定ダイアログにそれっぽい項目が現れます。ブラウザを指定してからチェックを入れてください。

ブラウザは"`chrome`"とか"`firefox`"てな感じで指定してください。(`to_sym`して`Selenium::WebDriver.for`に渡されます)

現状、ブラウザは起動直後にTweetDeckにログインした状態になっている必要があります。プロファイルとかをいい感じに弄ってうまくやってください。ごめんなさい。`UserConfig[:mikuttdeck_selenium_option]`を設定しておくと`Selenium::WebDriver.for`の第2引数に渡されます。

- Fifefoxの場合、あらかじめ`about:profiles`で"`mikutter`"のような適当な名前でプロファイルを作っておいて、mikutterコンソール(Alt+xで開きます)から`UserConfig[:mikuttdeck_selenium_option] = {profile: 'mikutter'}`を実行します。
- Google Chromeは`option`にSelenium由来のオブジェクトを渡す必要がありますが、こういうのを`UserConfig`に渡すのは禁止されているので、ダメです。mikutterコンソールから次を実行するととりあえず動く可能性があります(試していないのでわかりません)。

```rb
Plugin::Mikuttdeck::Deck.new(
  :chrome,
  desired_capabilities: Selenium::WebDriver::Remote::Capabilities.chrome(
    'chromeOption' => {
      'args' => ['--user-data-dir=/home/<username>/.confg/google-chrome/mikutter']
    }
  )
).start
```

# その他

- 人柱精神でおねがいします。
- 現状Homeタイムラインのみ吸っています。とはいえさすがに通知くらいは対応したいですね。
- 既知の問題として、mikutterの終了時にブラウザが終了しません。
- とりあえず動くようにしたレベルなので、当面内部実装は非互換の変更の可能性があります。依存したプラグインを書いたりする場合は注意してください。
- 内部では`GET statuses/lookup`とかいうこんなことでもなければ使わなかったようなエンドポイントを呼んでいます。rate limitに注意。(なお、そういうわけでREST APIが死ぬと使えなくなります)
- 具体的な挙動としては、TweetDeckから`tweet_id`のリストだけ吸い上げて、それをRESTに投げて`Plugin::Twitter::Message`オブジェクトを得て`update`とかのイベントを発行しています。
- 不具合報告はIssuesへどうぞ。 [@Takemaro_001@twitter.com](https://twitter.com/Takemaro_001) でも大丈夫です。
    - 報告の前に既に解消されていないか確認してください(`cd ~/.mikutter/plugin/mikuttdeck; git pull`で最新の不安定版を受け取れます)
