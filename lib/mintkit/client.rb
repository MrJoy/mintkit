require "mechanize"
require "json"
require "mintkit/error"
require "csv"

module Mintkit

  class Client

    def initialize(username, password)

      @username, @password  = username, password
      @agent = Mechanize.new{|a| a.ssl_version, a.verify_mode = 'SSLv3', OpenSSL::SSL::VERIFY_NONE}
      login

    end

    # login to my account
    # get all the transactions
    def transactions
      raw_transactions = @agent.get("https://wwws.mint.com/transactionDownload.event?").body

      transos = []

      CSV::Converters[:string] = proc do |field|
        field.encode(ConverterEncoding) rescue field
      end

      transos = CSV.parse(raw_transactions, { :headers => true }).map do |row|
        puts row.inspect
        {
          :date                   => Date.strptime(row['Date'], '%m/%d/%Y'),
          :description            => row['Description'],
          :original_description   => row['Original Description'],
          :amount                 => row['Amount'].to_f,
          :type                   => row['Transaction Type'],
          :category               => row['Category'],
          :account                => row['Account Name'],
          :labels                 => row['Labels'],
          :notes                  => row['Notes'],
        }
      end

      if block_given?
        transos.each do |transaction|
          yield transaction
        end
      end
      transos
    end

    def accounts
      page = @agent.get('https://wwws.mint.com/overview.event')

      requeststring = %q#[{"args":{"types":["BANK","CREDIT","INVESTMENT","LOAN","MORTGAGE","OTHER_PROPERTY","REAL_ESTATE","VEHICLE","UNCLASSIFIED"]},"service":"MintAccountService","task":"getAccountsSortedByBalanceDescending","id":"8675309"}]#

      accounts = JSON.parse(@agent.post("https://wwws.mint.com/bundledServiceController.xevent?token=#{@token}",{"input" => requeststring}).body)["response"]["8675309"]["response"]

      accountlist = []
      accounts.each do |a|
        account = {
          :current_balance => a["currentBalance"],
          :login_status => a["fiLoginUIStatus"],
          :currency => a["currency"],
          :id => a["id"],
          :amount_due => a["dueAmt"],
          :name => a["name"],
          :value => a["value"],
          #:due_date => Date.strptime(a["dueDate"], '%m/%d/%Y'),
          :last_updated => Time.at(a["lastUpdated"]/1000).to_date,
          :last_updated_string => a["lastUpdatedInString"],
          :active => !!a["isActive"],
          :login_status => a["fiLoginStatus"],
          :account_type => a["accountType"],
          :date_added => Time.at(a["addAccountDate"]/1000).to_date
        }

        if block_given?
          yield account
        end

        accountlist << account

      end
      accountlist

    end

    # force a refresh on my account
    def refresh
      page = @agent.get('https://wwws.mint.com/overview.event')

      @agent.post("https://wwws.mint.com/refreshFILogins.xevent", {"token"=>@token})

      true

    end
  private

    def login

      page = @agent.get('https://wwws.mint.com/login.event')
      form = page.forms[2]
      form.username = @username
      form.password = @password
      page = @agent.submit(form,form.buttons.first)

      raise FailedLogin unless page.at('input').attributes["value"]
      @token = page.at('input#javascript-token').attributes['value'].value
    end

    def logout
      @agent.get('https://wwws.mint.com/logout.event?task=explicit')
      true
    end

    def remove_quotes(input)
        input.slice(1..-1).slice(0..-2)
    end

  end
end
