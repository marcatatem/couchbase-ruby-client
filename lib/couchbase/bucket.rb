# Author:: Couchbase <info@couchbase.com>
# Copyright:: 2011 Couchbase, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'uri'

module Couchbase

  # This class holds all info about Couchbase bucket. It's able to
  # refresh configuration dynamically using streaming URI.

  class Bucket
    attr_accessor :type, :hash_algorithm, :replicas_count, :servers, :vbuckets,
      :nodes, :streaming_uri

    # Perform initial configuration and start thread which will listen
    # for configuration update via +streaming_uri+. Server should push
    # update notification about adding or removing nodes from cluester.
    def initialize(pool_uri, config, credentials = nil)
      @pool_uri = URI.parse(pool_uri)
      @credentials = credentials
      setup(config)
      listen_for_config_changes
    end

    # Select next node for work with Couchbase. Currently it makes sense
    # only for couchdb API, because memcached client works using moxi.
    def next_node
      nodes.shuffle.first
    end

    # Perform configuration using configuration cache. It turn all URIs
    # into full form (with schema, host and port).
    def setup(config)
      @streaming_uri = @pool_uri.merge(config['streamingUri'])
      @uri = @pool_uri.merge(config['uri'])
      @type = config['bucketType']
      @name = config['name']
      @nodes = config['nodes'].map do |node|
        Node.new(node['status'],
                 node['hostname'].split(':').first,
                 node['ports'],
                 node['couchApiBase'])
      end
      if @type == 'membase'
        server_map = config['vBucketServerMap']
        @hash_algorithm = server_map['hashAlgorithm']
        @replicas_count = server_map['numReplicas']
        @servers = server_map['serverList']
        @vbuckets = server_map['vBucketMap']
      end
    end

    private

    # Run background thread to listen for configuration changes.
    # Rewrites configuration for each update. Curl::Multi uses select()
    # call when waiting for data, so is should be efficient use ruby
    # threads here.
    def listen_for_config_changes
      Thread.new do
        multi = Curl::Multi.new
        c = Curl::Easy.new(@streaming_uri.to_s) do |curl|
          curl.useragent = "couchbase-ruby-client/#{Couchbase::VERSION}"
          if @credentials
            curl.http_auth_types = :basic
            curl.username = @credentials[:username]
            curl.password = @credentials[:password]
          end
          curl.verbose = true if Kernel.respond_to?(:debugger)
          curl.on_body do |data|
            config = Yajl::Parser.parse(data)
            setup(config) if config
            data.length
          end
        end
        multi.add(c)
        multi.perform
      end
    end
  end
end
