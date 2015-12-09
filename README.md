# これは何

Amazonの購入履歴をCSVエクスポートするツールとそのためのRubyライブラリ。

2015-12-09 動作確認

Amazonの購入履歴ページのHTMLが変わると対応できない。

Ruby (2.2.2で確認) とFirefoxとWebDriverが必要。

# 使い方

準備

    $ bundle install --path=vendor/bundle

購入履歴ページデフォルトの過去6ヶ月の履歴で良い場合

    $ bundle exec ruby address@example.com
    ...


表示期間を調整したい場合

    $ bundle exec ruby -p address@example.com
    Press Enter when ready.
    (エンター押す)
    ...

よりうるさいログ

    $ bundle exec ruby -lDEBUG address@example.com

