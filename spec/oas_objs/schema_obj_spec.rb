require 'spec_helper'
require 'dssl_helper'

RSpec.describe OpenApi::DSL::SchemaObj do
  let(:default_in) { [:api, :action, 'test'] }
  let(:subject_key_path) { %i[ paths goods/action get parameters ] + [ 0, :schema ] }

  ctx 'when not pass schema type as Hash type' do
    api -> { query :id, Integer }, eq: { type: 'integer' }
    api -> { query :people, { name: String }, desc: '' }, include: { type: 'object' }
    api -> { query :people, { name: String } }, 'will not have key :schema cause cannot recognize schema type',
        raise: [NoMethodError, "undefined method `[]' for nil:NilClass"]
  end

  ctx 'when pass schema type as Hash type' do
    api -> { query :id, type: Integer }, eq: { type: 'integer' }
    api -> { query :people, type: { name: String } }, include: { type: 'object' }
  end

  desc :processed_type do
    context 'when not be one of the [Hash, Array, Symbol]' do
      context 'when in [ float double int32 int64 ]' do
        api -> { query :info, Float }, eq: { type: 'number', format: 'float' }
        api -> { query :info, 'double' }, eq: { type: 'number', format: 'double' }
        api -> { query :info, 'int32' }, eq: { type: 'integer', format: 'int32' }
      end

      context 'when in [ binary base64 ]' do
        api -> { query :info, 'binary' }, eq: { type: 'string', format: 'binary' }
      end

      context 'when be file' do
        api -> { query :info, 'file' }, eq: { type: 'string', format: OpenApi::Config.dft_file_format }
      end

      context 'when be datetime' do
        api -> { query :info, 'datetime' }, eq: { type: 'string', format: 'date-time' }
      end

      context 'when is string or constant (not the above)' do
        api -> { query :info, 'type' }, eq: { type: 'type' }
        api -> { query :info, ApiDoc }, eq: { type: 'apidoc' }
      end
    end

    context 'when be a Symbol' do
      api -> { query :info, :QueryPage }, 'should be a parameter ref', eq: { :$ref => '#components/schemas/QueryPage' }
    end

    context 'when be a Array' do
      api -> { query :info, Array[String] }, has_keys!: %i[ type items ]
      it { expect(type).to eq 'array' }
      it { expect(items).to eq type: 'string' }

      context 'when be a nested Array' do
        api -> { query :info, [[String]] }, has_keys!: %i[ type items ]
        it { expect(items).to have_keys %i[ type items ] }

        context 'with CombinedSchema' do
          api -> { query :info, [all_of: [String, Integer]] }, has_keys!: %i[ type items ]
          it('should be an array, which\'s items is combined') { expect(items).to have_keys :allOf }
        end

        wrong 'without CombinedSchema' do
          api -> { query :info, [String, Integer] }, has_keys!: %i[ type items ]
          it('should be also an array, which\'s items is combined `oneOf`') { expect(items).to have_keys :oneOf }
        end
      end
    end

    context 'when be a Hash' do
      context 'normal' do
        api -> { query :info, type: { name: String, age: Integer } }, has_keys!: %i[ type properties ]
        it('should be a object type') { expect(type).to eq 'object' }
        it { expect(properties).to have_keys %i[ name age ] }
      end

      context "when property's name match !" do
        api -> { query :info, type: { name!: String, age: Integer } }, has_keys!: %i[ type required properties ]
        it('should make prop `name` required') { expect(required).to eq ['name'] }
        it { expect(properties).to have_keys %i[ name age ] }
      end

      context 'when be a nested Hash' do
        api -> { query :info, type: { name: { first: String, last!: String } } }, has_keys!: %i[ type properties ]
        focus_on :properties, :name
        expect_its :type, eq: 'object'
        expect_its :required, eq: ['last']
        expect_its :properties, has_keys: %i[ first last ]
      end

      context 'with key :type' do
        # OR: query :info, type: { type: String, desc: 'info' }
        api -> { query :info, { type: String, desc: 'info' }, desc: 'api desc' }, 'should have description within schema',
            has_key!: :description
        it { expect(description).to eq 'info' } # not_to eq 'api desc'
      end

      context 'when having keys in [ one_of any_of all_of not ]' do
        api -> { query :combination, one_of: [ :GoodSchema, String, { type: Integer, enum: [1, 2] } ] },
            'should be a combined schema', has_key!: :oneOf
        focus_on :one_of
        expect_it { have_size 3 }
        expect_its 0, eq: { :$ref => '#components/schemas/GoodSchema' }
        expect_its -1, eq: { type: 'integer', enum: [1, 2] }
      end
    end
  end


  desc :processed_enum_and_length do
    context 'when length is an array' do
      api -> { query :info, String, lth: [min = 1, max = 10] }, has_key!: %i[ minLength maxLength ]
      it { expect(min_length).to eq 1 }
      it { expect(max_length).to eq 10 }
    end

    context 'when length is a string' do
      api -> { query :info, String, lth: 'ge_10' }, has_key!: %i[ maxLength ]
      it { expect(max_length).to eq 10 }
      it { is_expected.not_to have_keys :minLength }
    end

    context 'when setting the size for the Array type' do
      api -> { query :info, [ ], size: [min = 10, max = 20] }, has_key!: %i[ minItems maxItems ]
      it { expect(min_items).to eq 10 }
      it { expect(max_items).to eq 20 }
    end

    context 'when enum is or not an array' do
      api -> { query :info, String, enum: ['a'] }, include: { enum: ['a'] }
      api -> { query :info, String, enum: 'a' }, include: { enum: ['a'] }
    end

    context 'when using must_be (value)' do
      api -> { query :info, String, must_be: 'a' }, 'should be also enum', include: { enum: ['a'] }
    end

    context 'when passing Range to lth' do
      api -> { query :info, String, lth: (1.4..5.5) }, has_key!: %i[ minLength maxLength ]
      it { expect(min_length).to eq 1 }
      it { expect(max_length).to eq 5 }
    end

    context 'when passing Range to enum' do
      api -> { query :info, String, enum: (1.2..3.4) }, has_key!: :enum
      it { expect(enum).to have_size ('1.2'..'3.4').to_a.size }
    end

    let(:description) { %i[ paths goods/action get parameters ].reduce(OpenApi.docs[:zro], &:[])[0][:description] }

    context 'when passing Array to enum!' do
      api -> { query :info, String, enum!: %w[ a b ], desc!: 'info: ' }, has_key!: :enum
      it { expect(description).to eq 'info: <br/>1/ a<br/>2/ b' }

      context 'when not passing desc!' do
        api -> { query :info, String, enum!: %w[ a b ] }, has_key!: :enum
        it('parameter should not have desc') { expect(description).to eq nil }
      end
    end

    context 'when passing Hash to enum!' do
      api -> { query :info, String, enum!: { 'desc1': :a, 'desc2': :b }, desc!: 'info: ' }, has_key!: :enum
      it { expect(description).to eq 'info: <br/>1/ desc1: a<br/>2/ desc2: b' }
    end
  end


  desc :processed_range do
    correct do
      api -> { query :info, Integer, range: { ge: 1, lt: 5 } }, include: { minimum: 1, maximum: 5, exclusiveMaximum: true }
    end
  end


  desc :processed_is_and_format do
    correct do
      api -> { query :email, Integer, is: :email }, include: { is: :email, format: :email }
    end
  end


  desc :process do
    describe ':pattern' do
      api -> { query :info, String, pattern: /\A[^@\s]+@[^@\s]+\z/ }, has_key!: :pattern
      it { expect(Regexp.new(pattern)).to eq /\A[^@\s]+@[^@\s]+\z/ }

      context 'when pattern is not regexp, but is a time format String' do
        api -> { query :info, DateTime, pattern: 'YY-MM-DD'}, has_key!: :pattern
        it { expect(pattern).to eq 'YY-MM-DD' }
      end
    end

    describe ':default' do
      api -> { query :info, String, dft: 'default' }, include: { default: 'default' }
    end

    describe ':examples' do
      api -> { query :info, { name: String, age: Integer }, examples: { input1: ['a', 1], input2: ['b, 2'] }, exp_by: %i[ name age ] },
          has_key!: :examples
      focus_on :examples
      expect_its 0, eq: { input1: { value: { name: 'a', age: 1 } } }
    end
  end
end
