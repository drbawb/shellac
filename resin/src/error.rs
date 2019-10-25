use failure::Fail;
use std::io;

#[derive(Debug, Fail)]
pub enum InternalError {
	#[fail(display = "internal io error: {}", inner)]
	IoError { inner: io::Error },

	#[fail(display = "fail serializing payload: {}", inner)]
	SerializerError { inner: serde_cbor::error::Error },
}

impl From<io::Error> for InternalError {
	fn from(error: io::Error) -> Self {
		InternalError::IoError { inner: error }
	}
}

impl From<serde_cbor::error::Error> for InternalError {
	fn from(error: serde_cbor::error::Error) -> Self {
		InternalError::SerializerError { inner: error }
	}
}
