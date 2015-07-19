__0.2.0__ 
   Changes:

          - Low-level sockets were replaced by network-conduit-tls
            (Be aware that this change might introduce some
             subtle changes in behaviour concerning in particular 
             performance and connection handling)

          - OMaxRecv not used anymore

          - New Option OTLS for TLS connections

          - New Option OTmo to specify a connection timeout

__0.1.4__ 
   Changes:

          - New: destroyReader and destroyWriter

          - Patterns deprecated

__0.1.3__ 
   New Option for newWriter 'ONoContentLen'


__0.1.2__ 
   Minor changes:

          - Dependency for stompl-0.1.1

          - Some more enquiries into potential mem leaks,
            but more to follow

__0.1.1__ 
   Dependency for bytestring 0.10

__0.1.0__ 
   Major changes:

          - Compliance with Stomp 1.2:

          - There are major changes in the frame format,
            please refer to the documentation of the 
            stompl package, version 0.1.0, there are important changes
            that may impact messages for older versions!

          - When generating an Ack frame,
            the *id* header is by default taken from the *ack* header
            in the corresponding Message frame.
            Should there be no *ack* header or if its value is empty,
            the value of the header *message-id* is taken.
            This behaviour complies with 1.2 
            for brokers supporting this version,
            but also continues to work with 1.1 brokers.

          - It is now possible to send a Stomp frame
            to connect to a broker (the broker, of course,
            has to accept Stomp frames and process them correctly).
            There is a new Copt (*OStomp*) to support this feature.

__0.0.8__ 
   Client/Server on top of Queues.

__0.0.7__ 
   Fighting with hackagedb...

__0.0.6__ 
      Heartbeats caused a memory leak by creating 
      many Connection instances in the connection state list.
      The connections were lazily deleted, i.e. were
      not deleted at all.
      Connection state is now cleaned up by a strict delete.

__0.0.5__ 
   Major changes:

          - Underscore functions (*withConnection_*) removed; 

          - New *with* functions: *withWriter*, *withPair*;

          - New option for connection (ClientId);

          - Headers for broker-specific options can be passed to connection
            (this changes the *withConnection* type signature!)

__0.0.3__ 
   New interface writeAdHoc

__0.0.2__ 
   Minor corrections

__0.0.1__ 
   Initial release
