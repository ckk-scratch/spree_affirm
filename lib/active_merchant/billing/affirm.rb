module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class Affirm < Gateway
      self.supported_countries = %w(US)
      self.default_currency = 'USD'
      self.money_format = :cents

      def initialize(options = {})
          requires!(options, :api_key, :secret_key, :server)
          @api_key = options[:api_key]
          @secret_key = options[:secret_key]
          super
      end

      def set_charge(source_or_charge)
          @charge_id = (source_or_charge.is_a? String) ? source_or_charge : source_or_charge.charge_id
      end

      def authorize(money, affirm_source, options = {})
        set_charge(affirm_source)
        result = commit(:get, "#{@charge_id}", nil, options)
        puts "comparing #{result.params["amount"]} against #{money} cents: #{amount(money)}"
        if amount(money).to_i != result.params["amount"].to_i
          return Response.new(false,
                              "Auth amount does not match charge amount",
                              result.params
                             )
        end
        if result.params["pending"].to_s != "true"
          return Response.new(false,
                              "Auth amount does not match charge amount",
                              result.params
                             )
        end
        result
      end

      # To create a charge on a card or a token, call
      #
      #   purchase(money, card_hash_or_token, { ... })
      #
      # To create a charge on a customer, call
      #
      #   purchase(money, nil, { :customer => id, ... })
      def purchase(money, affirm_source, options = {})
          capture(money, affirm_source, options)
      end

      def capture(money, charge_source, options = {})
        post = {:amount => amount(money)}
        set_charge(charge_source)
        result = commit(:post, "#{@charge_id}/capture", post, options)
        if amount(money).to_i != result.params["amount"].to_i
            return Response.new(false,
                       "Capture amount does not match charge amount",
                       result.params
                      )
        end
        result
      end

      def void(charge_source, options = {})
        puts "VOID  charge: #{charge_source.inspect}"
        set_charge(charge_source)
        commit(:post, "#{@charge_id}/void", {}, options)
      end

      def refund(money, charge_source, options = {})
        puts "REFUND  amount: #{money.inspect} charge: #{charge_source.inspect}"
        post = {:amount => amount(money)}
        set_charge(charge_source)
        commit(:post, "#{@charge_id}/refund", post, options)
      end

      def credit(money, charge_source, options = {})
          set_charge(charge_source)
          return Response.new(true ,
                       "Credited Zero amount",
                       {},
                       :authorization => @charge_id,
                      ) unless money > 0
          refund(money, charge_source, options)
      end

      def root_url
          "https://#{@options[:server]}/api/v2/charges/"
      end

      def headers
          {
              "Content-Type" => "application/json",
              "Authorization" => "Basic " + Base64.encode64(@api_key.to_s + ":" + @secret_key.to_s).gsub(/\n/, '').strip,
              "User-Agent" => "Affirm/v1 ActiveMerchantBindings",
          }
      end

      def parse(body)
        JSON.parse(body)
      end

      def post_data(params)
        return nil unless params
        params.to_json
      end
        
      def response_error(raw_response)
        begin
          parse(raw_response)
        rescue JSON::ParserError
          json_error(raw_response)
        end
      end

      def json_error(raw_response)
        msg = 'Invalid response.  Please contact affirm if you continue to receive this message.'
        msg += "  (The raw response returned by the API was #{raw_response.inspect})"
        {
          "error" => {
            "message" => msg
          }
        }
      end

      def commit(method, url, parameters=nil, options = {})
          raw_response = response = nil
          success = false
          begin
              puts "Making a #{method} to #{root_url + url} with #{post_data(parameters)}"
              puts "headers are #{headers.inspect}"
              raw_response = ssl_request(method, root_url + url, post_data(parameters), headers)
              response = parse(raw_response)
              success = !response.key?("status_code")
          rescue ResponseError => e
              raw_response = e.response.body
              response = response_error(raw_response)
          rescue JSON::ParserError
              response = json_error(raw_response)
          end

          puts "Affirm response is #{response.inspect}"
          Response.new(success,
                       success ? "Transaction approved" : response["message"],
                       response,
                       :authorization => @charge_id,
                      )
      end
    end
  end
end
