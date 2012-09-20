require 'new_relic/agent/instrumentation/controller_instrumentation'

DependencyDetection.defer do
  @name = :padrino_controller
  depends_on do
    defined?(::Padrino)
  end

  executes do
    ::Padrino::Application.class_eval do
      include PadrinoRpm::Instrumentation::PadrinoController
      alias dispatch_without_newrelic dispatch!
      alias dispatch! dispatch_with_newrelic
    end
  end
end

DependencyDetection.defer do
  @name = :padrino_view

  depends_on do
    defined?(::Padrino)
  end

  executes do
    NewRelic::Agent.logger.debug 'Installing Padrino view instrumentation'
  end

  executes do
    ::Padrino::Application.class_eval do
      include PadrinoRpm::Instrumentation::PadrinoView
      alias render_without_newrelic_trace render
      alias render render_with_newrelic_trace
    end
  end
end

module PadrinoRpm
  module Instrumentation
    module PadrinoController
      include NewRelic::Agent::Instrumentation::ControllerInstrumentation

      def dispatch_with_newrelic(*args, &block)
        route_info = recognize_route_for_newrelic
        perform_action_with_newrelic_trace({category: :controller, params: request.params}.merge(route_info)) do
          dispatch_without_newrelic
        end
      end

      def recognize_route_for_newrelic
        route_info = {
          name: '(unknown)',
          class_name: 'Unknown'
        }

        recognized_route = self.class.router.recognize(@env)
        if recognized_route && (route_name = recognized_route.first.path.route.named.to_s) && !route_name.empty?
          route_info[:name] = route_name
          route_info[:class_name] = route_name.split('_').first.capitalize
        #else
          #logger.warn "ROUTE NOT RECOGNIZED #{@env['PATH_INFO']}"
        end

        #logger.debug "New Relic route: #{route_info}"

        route_info
      end
    end

    module PadrinoView
      def render_with_newrelic_trace(*args, &block)
        engine, file = *args
        return render_without_newrelic_trace(*args, &block) if file == "= yield"

        file = "Proc" if file.is_a?(Proc)
        metrics = ["View/#{engine}/#{file.to_s.gsub(/\A\/+/, '')}/Rendering"]

        self.class.trace_execution_scoped metrics do
          render_without_newrelic_trace(*args, &block)
        end
      end
    end
  end
end

DependencyDetection.detect!


