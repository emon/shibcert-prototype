#!/usr/bin/env /usr/home/rails/shibcert/bin/rails runner
# coding: utf-8
# Local Variables:
# mode: ruby
# End:

require 'rubygems'
require 'mechanize'
require 'mail'
require 'zipruby'
require 'pp'
require 'logger'


class MailProcessor
  @mail = nil
  
  def initialize()
    @logger = Logger.new('log/mail_processor.log')
    @logger.progname = "#{$0}[#{$$}]"
    @logger.info("start")
  end

  def read_from(stream, maxlen=50000)
    mail_eml = ARGF.read(maxlen)
    if mail_eml.size >= maxlen
      logger.info("exit: too large mail (>#{maxlen.to_s})")
      exit
    end
    @mail = Mail.read_from_string(mail_eml)
    unless @mail.from == ['ca-support@ml.secom-sts.co.jp']
      logger.info("exit: skip From: #{@mail.from}")
      exit
    end

    unless @mail.parts[1].content_type == 'application/pkcs7-signature; name=smime.p7s; smime-type=signed-data'
      logger.info("exit: no digital signature found")
      exit
    end
  end

  def get_info
    unless @mail
      @logger.error("mail type: no mail info")
      return nil
    end

    case @mail.subject
    when '[UPKI] アクセスPIN発行通知'
      @logger.info("mail type: access PIN")
      self.get_pin
    when '[UPKI] クライアント証明書取得通知'
      @logger.info("mail type: serial number")
      self.get_serial
    else
      @logger.info("mail type: unknown, exit")
      return nil
    end
  end
  
  def get_pin
    unless @mail
      @logger.error("get_pin: no mail info")
      return nil
    end
    url = @mail.text_part.decoded.match(/https:\/\/scia.secomtrust.net\/[-=%\.\/\?\w]+/)
    @logger.info("URL: #{url}")

    agent = Mechanize.new

    page = agent.get(url)
    unless page.form_with
      @logger.info('mechanize: error stop, no form with spEntranceCliPin.do')
      return nil
    end
    page = page.form_with(:action => '/upki-odcert/download/spEntranceCliPin.do').submit

    unless page.form_with
      @logger.info('mechanize: error stop, no form with spDLCliPin.do')
      return nil
    end
    page = page.form_with(:action => '/upki-odcert/download/spDLCliPin.do').submit

    zipstream = page.body       # ZIP binary
    
    Zip::Archive.open_buffer(zipstream) do |ar|
      ar.each do |f|
        record = f.readlines[1].split("\t") # 2nd line Tab separate
        pin = record[2]         # PIN: 3rd column
        dn = record[1000]       # DN: ? column xxxxxxxxxxxxxx
        @logger.info("PIN: #{pin}")
        return ["pin", pin]     # normal
      end
    end
    return nil                  # abnormal
  end

  def get_serial
    mail_text_part = @mail.text_part.decoded
    mail_text_part.match(/^【対象証明書DN】\n　---------------------------------------------\n(.*)\n　---------------------------------------------$/m)
    dn = Regexp.last_match(1).delete('　').split("\n").join(',')

    mail_text_part.match(/^【対象証明書シリアル番号】\n　(\d+)$/m)
    serial = Regexp.last_match(1)

    @logger.info("DN: #{dn}")
    @logger.info("serial: #{serial}")
    return ["serial", dn, serial]
  end
end

MAIL_MAXLEN = 50000

mailprocessor = MailProcessor.new()
mailprocessor.read_from(ARGF, MAIL_MAXLEN)
rec = mailprocessor.get_info    # ["pin", "CN=...C=JP", "12345ABCDE"] or ["serial", "CN=...C=JP", "123456789"]
p rec

certs = Cert.all                # ActiveRecord

# ToDo
# rec の情報を certs に反映させる
# DN と cert_state_id で検索をかけて，該当するレコードの pin または cert_serial を登録する


=begin

Subject: [UPKI] クライアント証明書取得通知

【対象証明書DN】
　---------------------------------------------
　CN=taro000kyoto
　OU=001
　OU=Kyoto University Integrated Information Network System
　O=Kyoto University
　L=Academe
　C=JP
　---------------------------------------------

【対象証明書シリアル番号】
　4097000000000000000
=end
