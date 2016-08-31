# これは何

Amazonの購入履歴をCSVエクスポートするツールとそのためのRubyライブラリ。

2016-08-31 最終動作確認

* Ruby (2.3.1で動作確認)、FirefoxとWebDriverが必要。
 * 使用しているFirefoxのバージョンとWebDriverのバージョンの不整合で動作しなくなることがある
  * WebDriverがFirefoxのバージョンに追随するかFirefoxが対応をしないと動かない……
 * Amazonの購入履歴ページのHTMLが変わると対応できないのでそのときは諦めて


# 使い方

準備

    $ bundle install --path=vendor/bundle

購入履歴ページデフォルトの過去6ヶ月の履歴で良い場合

    $ bundle exec ruby check_purchases.rb address@example.com
    ...


表示期間を調整したい場合

    $ bundle exec ruby check_purchases.rb -p address@example.com
    password for "address@example.com": (パスワードを入力する)
    Press Enter when ready.
    (エンター押す)
    ...

よりうるさいログを表示する場合は `-lDEBUG` とする。

    $ bundle exec ruby check_purchases.rb -lDEBUG address@example.com

`--drop-before` と `--drop-after` で取得範囲を制限できる。

    $ bundle exec ruby check_purchases.rb --drop-before 2016-03-01 address@example.com
