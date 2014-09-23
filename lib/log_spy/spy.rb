require 'aws-sdk'
require 'rack'
require 'log_spy/payload'
require 'json'
require 'ostruct'

class LogSpy::Spy
  attr_reader :sqs_thread
  def initialize(app, sqs_url, options = {})
    @app = app
    @sqs_url = sqs_url
    @options = options
  end

  def call env
    @env = env
    @start_time = Time.now.to_f
    @status, header, body = @app.call(env)

    @sqs_thread = send_sqs_async

    [ @status, header, body ]
  rescue Exception => err
    @sqs_thread = send_sqs_async(err)
    raise err
  end

  def req
    r = Rack::Request.new @env
    if controller_params = @env['action_dispatch.request.parameters']
      r['controller_action'] = "#{controller_params['controller']}##{controller_params['action']}"
    end
    r
  end
  private :req

  def send_sqs_async(err = nil)
    @sqs_thread = Thread.new do
      status = err ? 500 : @status
      sqs = AWS::SQS.new(@options)
      duration = ( (Time.now.to_f - @start_time) * 1000 ).round(0)
      res = OpenStruct.new({
        :duration => duration,
        :status => status
      })
      payload = ::LogSpy::Payload.new(req, res, @start_time.to_i, err)

      sqs.queues[@sqs_url].send_message(payload.to_json)
    end
  end
  private :send_sqs_async
end
