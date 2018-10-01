# frozen_string_literal: true
require "kennel"

# Show Alerts that are not muted and their alerting scopes
module Kennel
  class UnmutedAlerts
    class << self
      def print(api, tag)
        monitors = filtered_monitors(api, tag)
        if monitors.empty?
          puts "No unmuted alerts found"
        else
          monitors.each do |m|
            puts m[:name]
            puts Utils.path_to_url("/monitors/#{m[:id]}")
            m[:state][:groups].each { |g| puts "#{g[:status]}\t#{g[:name]}" }
            puts
          end
        end
      end

      private

      # sort pod3 before pod11
      def sort_groups!(monitor)
        groups = monitor[:state][:groups].values
        groups.sort_by! { |g| g[:name].to_s.split(",").map { |w| Utils.natural_order(w) } }
        monitor[:state][:groups] = groups
      end

      def filtered_monitors(api, tag)
        # Download all monitors
        monitors = Progress.progress("Downloading") do
          api.list("monitor")
        end

        # only keep monitors from selected tag
        monitors.select! { |m| m[:tags].include? tag }
        raise "No monitors for #{tag} found, check your spelling" if monitors.empty?

        # only keep monitors that are alerting or not silenced
        monitors.select! { |m| m[:overall_state] != "OK" && !m[:options][:silenced].key?(:*) }

        # get state details to romove silenced alerts
        Progress.progress("Getting monitor details") do
          monitors = Utils.parallel(monitors) do |m|
            api.show("monitor", m.fetch(:id), group_states: "all")
          end
        end

        # only keep groups that are alerting
        monitors.each { |m| m[:state][:groups].reject! { |_, g| g[:status] == "OK" } }

        # only keep alerting groups that are not silenced
        monitors.each do |m|
          silenced = m[:options][:silenced].keys.map { |k| k.to_s.split(",") }
          m[:state][:groups].select! do |k, _|
            scope = k.to_s.split(",")
            silenced.none? { |s| (s - scope).empty? }
          end
        end

        # only keep monitors with alerting groups
        monitors.select! { |m| m[:state][:groups].any? }

        # sort group alerts
        monitors.each { |m| sort_groups!(m) }
      end
    end
  end
end