#--
# Copyright (c) 2011-2011, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files(the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Japan.
#++

require 'mongo'

#require 'rufus-json'
require 'ruote/storage/base'
require 'ruote/mon/version'


module Ruote
module Mon

  class Storage

    include Ruote::StorageBase

    attr_reader :db

    def initialize(mongo_db, options={})

      @db = mongo_db
      @options = options

      # TODO: add indexes

      replace_engine_configuration(options)
    end

    # Returns true if the doc is successfully deleted.
    #
    def reserve(doc)

      r = collection(doc).remove(
        { '_id' => doc['_id'], '_rev' => doc['_rev'] },
        :safe => true)

      r['n'] == 1
    end

    def put(doc, opts={})

      original = doc
      doc = doc.dup

      doc['_rev'] = (doc['_rev'] || -1) + 1
      doc['_tail_id'] ||= doc['_id'].split('!').last
      doc['put_at'] = Ruote.now_to_utc_s

      r = begin
        collection(doc).update(
          { '_id' => doc['_id'], '_rev' => original['_rev'] },
          doc,
          :safe => true, :upsert => original['_rev'].nil?)
      rescue Mongo::OperationFailure
        false
      end

      if r && (r['updatedExisting'] || original['_rev'].nil?)
        original['_rev'] = doc['_rev'] if opts[:update_rev]
        nil
      else
        collection(doc).find_one('_id' => doc['_id']) || true
      end
    end

    def get(type, key)

      collection(type).find_one('_id' => key)
    end

    def delete(doc)

      rev = doc['_rev']

      raise ArgumentError.new("can't delete doc without _rev") unless rev

      r = collection(doc).remove(
        { '_id' => doc['_id'], '_rev' => doc['_rev'] },
        :safe => true)

      if r['n'] == 1
        nil
      else
        collection(doc).find_one('_id' => doc['_id']) || true
      end
    end

    def get_many(type, key=nil, opts={})

      opts = Ruote.keys_to_s(opts)

      cursor = if key.nil?
        collection(type).find
      elsif key.is_a?(Regexp)
        collection(type).find('_id' => key)
      else # a String
        collection(type).find('_tail_id' => key)
      end

      return cursor.count if opts['count']

      cursor.sort(
        '_id', opts['descending'] ? Mongo::DESCENDING : Mongo::ASCENDING)

      cursor.skip(opts['skip'])
      cursor.limit(opts['limit'])

      cursor.to_a
    end

    def ids(type)

      collection(type).find(
        {},
        :fields => [], :sort => [ '_id', Mongo::ASCENDING ]
      ).collect { |d|
        d['_id']
      }
    end

    def purge!

      TYPES.each { |t| collection(t).remove }
    end

    # Returns a String containing a representation of the current content of
    # in this Redis storage.
    #
    def dump(type)

      r = [ "== #{type} ==" ]

      collection(type).find.inject(r) { |a, doc|
        a << doc.inspect
      }.join("\n")
    end

    # Shuts this storage down.
    #
    def close
    end

    # Shuts this worker down.
    #
    def shutdown
    end

    # Mainly used by ruote's test/unit/ut_17_storage.rb
    #
    def add_type(type)

      # nothing to be done
    end

    # Nukes a db type and reputs it(losing all the documents that were in it).
    #
    def purge_type!(type)

      collection(type).remove
    end

    protected

    def collection(doc_or_type)

      @db.collection(
        doc_or_type.is_a?(String) ? doc_or_type : doc_or_type['type'])
    end
  end
end
end
