require 'spec_helper'
require 'benchmark'

describe Server do
  let(:port) { random_port }
  let(:client) do
    CoAP::Client.new(port: port, retransmit: false, recv_timeout: 0.1)
  end

  let!(:server) { supervised_server(:Port => port, :Log => debug) }

  context 'ordinary request' do
    subject { client.get('/hello', '::1') }

    it 'should be plausible' do
      expect(subject).to be_a(CoAP::Message)
      expect(subject.ver).to eq(1)
      expect(subject.tt).to eq(:ack)
      expect(subject.mcode).to eq([2, 5])
      expect(subject.payload).to eq('Hello World!')
    end
  end

  context 'missing resource' do
    subject { client.get('/404', '::1') }

    it 'should be 4.04' do
      expect(subject).to be_a(CoAP::Message)
      expect(subject.ver).to eq(1)
      expect(subject.tt).to eq(:ack)
      expect(subject.mcode).to eq([4, 4])
      expect(subject.payload).to eq('')
    end
  end

  context 'unsupported method' do
    subject { client.delete('/hello', '::1') }

    it 'should be 4.05' do
      expect(subject).to be_a(CoAP::Message)
      expect(subject.ver).to eq(1)
      expect(subject.tt).to eq(:ack)
      expect(subject.mcode).to eq([4, 5])
      expect(subject.payload).to eq('')
    end
  end

  # See https://tools.ietf.org/html/rfc7252#section-12.8
  context 'multicast' do
    # -A INPUT -m pkttype --pkt-type multicast -d ff02::fd -j ACCEPT
    context 'ipv6', multicast: :ipv6 do
      ['ff02::1', 'ff02::fd', 'ff05::fd'].each do |address|
        context address do
          subject { client.get('/hello', address) }

          it 'should be 2.05' do
            expect(subject).to be_a(CoAP::Message)
            expect(subject.ver).to eq(1)
            expect(subject.tt).to eq(:ack)
            expect(subject.mcode).to eq([2, 5])
            expect(subject.payload).to eq('Hello World!')
          end
        end
      end
    end

    # -A INPUT -m pkttype --pkt-type multicast -d 224.0.1.187 -j ACCEPT
    context 'ipv4', multicast: :ipv4 do
      let!(:server) do
        supervised_server(:Host => '0.0.0.0', :Port => port, :Log => debug)
      end

      ['224.0.0.1', '224.0.1.187'].each do |address|
        context address do
          subject { client.get('/hello', address) }

          it 'should be 2.05' do
            expect(subject).to be_a(CoAP::Message)
            expect(subject.ver).to eq(1)
            expect(subject.tt).to eq(:ack)
            expect(subject.mcode).to eq([2, 5])
            expect(subject.payload).to eq('Hello World!')
          end
        end
      end
    end
  end

  context 'block' do
    context 'block2.more set' do
      subject { client.get('/', '::1', nil, nil, block2: 14) }

      it 'should be an error' do
        expect(subject).to be_a(CoAP::Message)
        expect(subject.ver).to eq(1)
        expect(subject.tt).to eq(:ack)
        expect(subject.mcode).to eq([4, 5])
        expect(subject.payload).to eq('')
      end
    end

    context 'non existent' do
      let(:client) do
        CoAP::Client.new \
          port: port,
          retransmit: false,
          recv_timeout: 0.1
      end

      subject { client.get('/hello', '::1', nil, nil, block2: 16) }

      it 'should be an error' do
        expect { subject }.to raise_error(Timeout::Error)
      end
    end

    context 'transfer' do
      subject do
        [0, 16].map do |x|
          client.get('/block', '::1', nil, nil, block2: x)
        end
      end

      it { expect(subject[0].mcode).to eq([2, 5]) }
      it { expect(subject[0].payload.bytesize).to eq(16) }

      it { expect(subject[1].mcode).to eq([2, 5]) }
      it { expect(subject[1].payload.bytesize).to eq(1) }
    end
  end

  after do
    server.terminate
  end
end
